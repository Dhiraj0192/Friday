import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/task_history_entry.dart';
import 'friday_profile.dart';
import 'screen_automation_service.dart';
import 'brain_router.dart';
import 'settings_service.dart';
import 'system_control_service.dart';
import 'system_diagnostics_service.dart';
import 'task_executor.dart';

/// Where the bus lives and Friday's token for it, from Sir's pairing code.
class BusLink {
  const BusLink(this.url, this.token);
  final Uri url;
  final String token;
}

/// The envelope rules, kept in step with ~/Work/jarvis/phone/bus.py.
class BusCodec {
  static const pairingPrefix = 'friday1:';
  static const version = 1;
  static const maxBytes = 16 * 1024;
  static const maxText = 8000;
  static const maxHops = 2;
  static const defaultTtl = 900;
  static const jarvisKinds = {'ask', 'reply', 'notice'};
  static final _id = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  /// `friday1:` + unpadded base64url of `{"url", "token"}`, as printed by
  /// `server.py pair-friday` on the laptop. Throws [FormatException].
  static BusLink decodePairing(String code) {
    final trimmed = code.trim();
    if (!trimmed.startsWith(pairingPrefix)) {
      throw const FormatException('Not a Friday pairing code.');
    }
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(trimmed.substring(pairingPrefix.length)))));
    } catch (_) {
      throw const FormatException('The pairing code is damaged.');
    }
    if (data is! Map) throw const FormatException('The pairing code is damaged.');
    final url = Uri.tryParse('${data['url'] ?? ''}');
    final token = '${data['token'] ?? ''}';
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('The pairing code needs the laptop\'s https address.');
    }
    if (token.length < 16) throw const FormatException('The pairing code has no token.');
    return BusLink(url, token);
  }

  /// An envelope from Friday to Jarvis.
  static Map<String, dynamic> make(
    String kind,
    String text, {
    String? replyTo,
    int hops = 0,
    int ttl = defaultTtl,
    double? now,
  }) {
    final ts = now ?? DateTime.now().millisecondsSinceEpoch / 1000;
    return {
      'v': version,
      'id': const Uuid().v4().replaceAll('-', ''),
      'from': 'friday',
      'to': 'jarvis',
      'kind': kind,
      'text': text.length > maxText ? text.substring(0, maxText) : text,
      'reply_to': replyTo,
      'risk': null,
      'hops': min(hops, maxHops),
      'ts': ts,
      'ttl': ttl,
    };
  }

  /// Jarvis's envelope, checked, or null when it is malformed, not for
  /// Friday, or already expired.
  static Map<String, dynamic>? validate(Object? raw, {double? now}) {
    if (raw is! Map) return null;
    final env = raw.map((k, v) => MapEntry('$k', v));
    final id = env['id'];
    final text = env['text'];
    final hops = env['hops'];
    final expires = env['expires'];
    final replyTo = env['reply_to'];
    final ts = now ?? DateTime.now().millisecondsSinceEpoch / 1000;
    if (env['v'] != version || env['from'] != 'jarvis' || env['to'] != 'friday') return null;
    if (id is! String || !_id.hasMatch(id)) return null;
    if (!jarvisKinds.contains(env['kind'])) return null;
    if (text is! String || text.trim().isEmpty || text.length > maxText) return null;
    if (hops is! int || hops < 0 || hops > maxHops) return null;
    if (expires is! num || expires <= ts) return null;
    if (env['kind'] == 'reply' && (replyTo is! String || !_id.hasMatch(replyTo))) return null;
    return env;
  }
}

/// Server-sent events, one line at a time: returns the event's data once
/// its blank line arrives. Comments (the heartbeat) and other fields are skipped.
class SseParser {
  final _data = <String>[];

  String? add(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) return null;
      final out = _data.join('\n');
      _data.clear();
      return out;
    }
    if (line.startsWith(':')) return null;
    if (line.startsWith('data:')) {
      final value = line.substring(5);
      _data.add(value.startsWith(' ') ? value.substring(1) : value);
    }
    return null;
  }
}

enum BusState { off, connecting, online, offline }

/// Friday's end of the Jarvis ⇄ Friday bus.
///
/// Jarvis → Friday: an SSE stream from the laptop phone server
/// (`GET /api/bus/events`), held open while the link is on and reconnected
/// with backoff. Each message is recorded, acked, then handled:
///  * `ask`: run only through [TaskExecutor.executeTask] with origin
///    'jarvis', so the risk gate asks Sir before anything that acts;
///    the outcome goes back as a reply.
///  * `reply`: answers one of Friday's [askJarvis] calls.
///  * `notice`: shown to Sir as a notification.
/// Friday → Jarvis: `POST /api/bus/send`; whatever cannot go now waits in
/// an outbox in prefs until the next connect. Ids drop resends both ways.
class BusService extends ChangeNotifier {
  BusService({
    http.Client Function()? client,
    BusLink? Function()? link,
    Future<String> Function(String goal)? runAsk,
    Future<void> Function(String text)? onNotice,
    Future<Map<String, dynamic>> Function()? statusReport,
    Future<String> Function()? profile,
  })  : _newClient = client ?? http.Client.new,
        _link = link ?? _savedLink,
        _runAsk = runAsk ?? _executeForJarvis,
        _onNotice = onNotice ?? _notify,
        _statusReport = statusReport ?? _phoneStatus,
        _profile = profile ?? FridayProfile.current;

  static final BusService instance = BusService();

  static const readTimeout = Duration(seconds: 60);
  static const statusEvery = Duration(seconds: 60);
  static const minBackoff = Duration(seconds: 2);
  static const maxBackoff = Duration(seconds: 60);
  static const askTimeout = Duration(seconds: 90);
  static const keepSeen = 300;
  static const keepOutbox = 50;
  static const _seenKey = 'jarvis_bus_seen';
  static const _outboxKey = 'jarvis_bus_outbox';
  static const _jarvisProfileKey = 'jarvis_profile_text';
  static const _jarvisProfileAtKey = 'jarvis_profile_at';
  static const profileEvery = Duration(hours: 24);
  static const maxJarvisProfile = 12000;

  final http.Client Function() _newClient;
  final BusLink? Function() _link;
  final Future<String> Function(String goal) _runAsk;
  final Future<void> Function(String text) _onNotice;
  final Future<Map<String, dynamic>> Function() _statusReport;
  final Future<String> Function() _profile;

  final _waiting = <String, Completer<String>>{};
  Future<void> _askChain = Future.value();
  http.Client? _client;
  Timer? _statusTimer;
  bool _running = false;

  BusState state = BusState.off;
  String? lastError;
  bool jarvisRunning = false;

  /// Jarvis's own profile, fetched from the laptop; empty until paired and fetched.
  String jarvisProfile = '';

  bool get isOnline => state == BusState.online;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Starts the link when it is paired and switched on; idempotent.
  void start() {
    if (_link() == null) {
      jarvisProfile = '';
      return;
    }
    if (_running) return;
    _running = true;
    unawaited(_loadJarvisProfile());
    unawaited(_loop());
  }

  void stop() {
    _running = false;
    _statusTimer?.cancel();
    _client?.close();
    _client = null;
    _set(BusState.off);
  }

  /// Applies a change of pairing or of the kill switch.
  void restart() {
    stop();
    start();
  }

  Future<void> _loop() async {
    var backoff = minBackoff;
    while (_running) {
      final connected = await connectOnce();
      if (!_running) break;
      if (connected) backoff = minBackoff;
      _set(BusState.offline);
      await Future<void>.delayed(backoff);
      backoff = Duration(seconds: min(backoff.inSeconds * 2, maxBackoff.inSeconds));
    }
  }

  /// One stream from connect to close. True when the laptop accepted it.
  @visibleForTesting
  Future<bool> connectOnce() async {
    final link = _link();
    if (link == null) return false;
    final client = _client = _newClient();
    _set(BusState.connecting);
    try {
      final request = http.Request('GET', link.url.resolve('/api/bus/events'))
        ..headers.addAll(_headers(link));
      final response = await client.send(request).timeout(readTimeout);
      if (response.statusCode != 200) {
        lastError = response.statusCode == 401
            ? 'Jarvis refused the token. Pair again.'
            : 'The laptop answered ${response.statusCode}.';
        return false;
      }
      lastError = null;
      _set(BusState.online);
      await _postStatus();
      await flushOutbox();
      unawaited(exchangeProfiles());
      _statusTimer?.cancel();
      _statusTimer = Timer.periodic(statusEvery, (_) => unawaited(_postStatus()));

      final parser = SseParser();
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(readTimeout);
      await for (final line in lines) {
        final data = parser.add(line);
        if (data == null) continue;
        try {
          await handle(jsonDecode(data));
        } on FormatException {
          continue;
        }
      }
      return true;
    } catch (e) {
      if (_running) lastError = 'Lost the laptop: $e';
      return state == BusState.online;
    } finally {
      _statusTimer?.cancel();
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  // ------------------------------------------------------------------
  // Jarvis → Friday
  // ------------------------------------------------------------------

  /// Records, acks, then acts on one message from Jarvis.
  @visibleForTesting
  Future<void> handle(Object? raw) async {
    final env = BusCodec.validate(raw);
    if (env == null) return;
    final id = env['id'] as String;
    final fresh = await _remember(id);
    await _ack(id);
    if (!fresh) return;

    final text = (env['text'] as String).trim();
    switch (env['kind']) {
      case 'reply':
        final waiter = _waiting.remove(env['reply_to']);
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete(text);
        } else {
          await _onNotice('Jarvis, late: $text');
        }
      case 'notice':
        await _onNotice(text);
      case 'ask':
        // One at a time, and never holding up the stream.
        _askChain = _askChain.then((_) => _answer(env, text));
    }
  }

  /// Settles once every ask received so far has been answered.
  @visibleForTesting
  Future<void> get idle => _askChain;

  Future<void> _answer(Map<String, dynamic> ask, String text) async {
    String answer;
    try {
      answer = await _runAsk(text);
    } catch (e) {
      answer = 'Friday could not do that: $e';
    }
    await send(BusCodec.make(
      'reply',
      answer,
      replyTo: ask['id'] as String,
      hops: (ask['hops'] as int) + 1,
    ));
  }

  // ------------------------------------------------------------------
  // Friday → Jarvis
  // ------------------------------------------------------------------

  /// Asks Jarvis and waits for his reply; null if he does not answer in time
  /// or the link is not set up. A reply after the wait arrives as a notice.
  Future<String?> askJarvis(String text, {Duration timeout = askTimeout}) async {
    if (_link() == null) return null;
    final env = BusCodec.make('ask', text);
    final id = env['id'] as String;
    final waiter = _waiting[id] = Completer<String>();
    await send(env);
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      _waiting.remove(id);
    }
  }

  /// Tells Jarvis something; no reply expected.
  Future<void> tellJarvis(String text) => send(BusCodec.make('notice', text));

  /// Posts [env], or keeps it in the outbox for the next connect.
  Future<bool> send(Map<String, dynamic> env) async {
    final link = _link();
    if (link == null) return false;
    try {
      final response = await _post(link, '/api/bus/send', env);
      if (response.statusCode == 200) {
        _noteJarvis(response.body);
        return true;
      }
      // A refusal (400) will not get better by retrying.
      if (response.statusCode == 400) return false;
    } catch (_) {
      // offline: falls through to the outbox
    }
    await _queue(env);
    return false;
  }

  /// Sends what waited while offline, oldest first; drops the expired.
  Future<void> flushOutbox() async {
    final link = _link();
    if (link == null) return;
    final prefs = await SharedPreferences.getInstance();
    final queued = _decodeList(prefs.getStringList(_outboxKey));
    if (queued.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final left = <Map<String, dynamic>>[];
    for (final env in queued) {
      if ((env['ts'] as num) + (env['ttl'] as num) <= now) continue;
      try {
        final response = await _post(link, '/api/bus/send', env);
        if (response.statusCode == 200 || response.statusCode == 400) continue;
      } catch (_) {
        // still offline
      }
      left.add(env);
    }
    await prefs.setStringList(_outboxKey, left.map(jsonEncode).toList());
  }

  Future<void> _queue(Map<String, dynamic> env) async {
    final prefs = await SharedPreferences.getInstance();
    final queued = [
      ...?prefs.getStringList(_outboxKey),
      jsonEncode(env),
    ];
    final start = max(0, queued.length - keepOutbox);
    await prefs.setStringList(_outboxKey, queued.sublist(start));
  }

  // ------------------------------------------------------------------
  // Plumbing
  // ------------------------------------------------------------------

  Future<bool> _remember(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey) ?? const [];
    if (seen.contains(id)) return false;
    final kept = [...seen, id];
    await prefs.setStringList(_seenKey, kept.sublist(max(0, kept.length - keepSeen)));
    return true;
  }

  Future<void> _ack(String id) async {
    final link = _link();
    if (link == null) return;
    try {
      await _post(link, '/api/bus/ack', {'id': id});
    } catch (_) {
      // unacked, it comes again on the next stream and is dropped as seen
    }
  }

  Future<void> _postStatus() async {
    final link = _link();
    if (link == null) return;
    try {
      final response = await _post(link, '/api/bus/status', await _statusReport());
      _noteJarvis(response.body);
    } catch (_) {
      // the stream will notice
    }
  }

  /// Each knows the other: hers goes up on every connect, his comes down daily.
  @visibleForTesting
  Future<void> exchangeProfiles({DateTime? now}) async {
    final link = _link();
    if (link == null) return;
    try {
      await _post(link, '/api/bus/friday-profile', {'text': await _profile()});
    } catch (_) {
      // next connect tries again
    }
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_jarvisProfileAtKey) ?? 0;
    final clock = now ?? DateTime.now();
    if (clock.millisecondsSinceEpoch - at < profileEvery.inMilliseconds &&
        (prefs.getString(_jarvisProfileKey) ?? '').isNotEmpty) {
      return;
    }
    try {
      final client = _client ?? _newClient();
      final response = await client
          .get(link.url.resolve('/api/bus/profile'), headers: _headers(link))
          .timeout(const Duration(seconds: 40));
      if (_client == null) client.close();
      if (response.statusCode != 200) return;
      final text = (jsonDecode(response.body) as Map<String, dynamic>)['text'];
      if (text is! String || text.trim().isEmpty) return;
      jarvisProfile = text.trim().length > maxJarvisProfile
          ? text.trim().substring(0, maxJarvisProfile)
          : text.trim();
      await prefs.setString(_jarvisProfileKey, jarvisProfile);
      await prefs.setInt(_jarvisProfileAtKey, clock.millisecondsSinceEpoch);
      notifyListeners();
    } catch (_) {
      // keep the cached copy
    }
  }

  Future<void> _loadJarvisProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (jarvisProfile.isEmpty) jarvisProfile = prefs.getString(_jarvisProfileKey) ?? '';
  }

  Future<http.Response> _post(BusLink link, String path, Object body) {
    final client = _client ?? _newClient();
    final future = client
        .post(
          link.url.resolve(path),
          headers: {..._headers(link), 'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (_client == null) future.whenComplete(client.close).ignore();
    return future;
  }

  Map<String, String> _headers(BusLink link) => {'authorization': 'Bearer ${link.token}'};

  void _noteJarvis(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['jarvis_running'] is bool) {
        jarvisRunning = data['jarvis_running'] as bool;
        notifyListeners();
      }
    } catch (_) {
      // not JSON; nothing to note
    }
  }

  void _set(BusState next) {
    if (state == next) return;
    state = next;
    notifyListeners();
  }

  static List<Map<String, dynamic>> _decodeList(List<String>? raw) {
    final out = <Map<String, dynamic>>[];
    for (final item in raw ?? const <String>[]) {
      try {
        final env = jsonDecode(item);
        if (env is Map<String, dynamic> && env['ts'] is num && env['ttl'] is num) out.add(env);
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Defaults on the phone
  // ------------------------------------------------------------------

  /// The saved pairing, when the Jarvis link is on; else null.
  static BusLink? get savedLink => _savedLink();

  static BusLink? _savedLink() {
    final settings = SettingsService.instance;
    if (!settings.jarvisLinkEnabled || !settings.isJarvisPaired) return null;
    final url = Uri.tryParse(settings.jarvisBusUrl);
    return url == null ? null : BusLink(url, settings.jarvisBusToken);
  }

  static Future<String> _executeForJarvis(String goal) async {
    final executor = TaskExecutor.instance;
    if (executor.isBusy) {
      return 'Friday is busy with "${executor.currentGoal ?? 'another task'}"; ask again shortly.';
    }
    final status = await executor.executeTask(goal, origin: 'jarvis');
    return report(status, answer: executor.lastAnswer, failure: executor.lastFailure);
  }

  /// What Jarvis hears when a task he asked for ends: on failure, the reason
  /// the phone logged, so he can tell Sir what to fix.
  static String report(TaskStatus status, {String? answer, String? failure}) =>
      switch (status) {
        TaskStatus.success => answer ?? 'Done.',
        TaskStatus.declined => 'Declined by Sir.',
        TaskStatus.cancelled => 'Cancelled on the phone.',
        TaskStatus.failed => switch (answer ?? failure) {
            null => 'Friday could not finish that.',
            final why => 'Could not finish: $why',
          },
      };

  static Future<void> _notify(String text) =>
      SystemControlService.instance.notify('Jarvis', text);

  static Future<Map<String, dynamic>> _phoneStatus() async {
    final diag = await SystemDiagnosticsService.instance.getDiagnostics() ?? const {};
    final settings = SettingsService.instance;
    return {
      if (diag['batteryLevel'] is int && (diag['batteryLevel'] as int) >= 0)
        'battery': diag['batteryLevel'],
      if (diag['isCharging'] is bool) 'charging': diag['isCharging'],
      'brain': BrainRouter.instance.offline.value ? 'on_device (laptop out of reach)' : settings.provider,
      'accessibility': await ScreenAutomationService.instance.isServiceEnabled(),
    };
  }
}
