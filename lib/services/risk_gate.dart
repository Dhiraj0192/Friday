import '../models/screen_node.dart';
import '../models/task_step.dart';

/// What an action would do that Sir must say yes to first. Reading, opening
/// and searching need no yes; everything here does, whoever asked for it.
enum RiskCategory { send, call, pay, delete, settings, install, power }

extension RiskCategoryText on RiskCategory {
  String get describe => switch (this) {
        RiskCategory.send => 'send or post something',
        RiskCategory.call => 'place a call',
        RiskCategory.pay => 'spend or move money',
        RiskCategory.delete => 'delete or remove something',
        RiskCategory.settings => 'change a setting or permission',
        RiskCategory.install => 'install or update an app',
        RiskCategory.power => 'restart, power off or sign out',
      };
}

/// One thing waiting for Sir's yes.
class RiskRequest {
  const RiskRequest({required this.category, required this.what, this.origin});

  final RiskCategory category;

  /// Plain words for the approval prompt: the goal, or the button about to be tapped.
  final String what;

  /// Who asked: null for Sir himself on the phone, else e.g. 'jarvis'.
  final String? origin;

  String get prompt =>
      '${origin == null ? 'This' : 'A request from ${origin![0].toUpperCase()}${origin!.substring(1)}'}'
      ' would ${category.describe}: "$what". Allow it?';
}

typedef RiskApprover = Future<bool> Function(RiskRequest request);

/// The single gate every phone action passes through: the agent loop's goal
/// and each of its steps, from Sir's own commands and from the Jarvis bus.
/// With no approver installed it refuses (fails closed).
class RiskGate {
  RiskGate._();

  static RiskApprover? approver;

  static Future<bool> approve(RiskRequest request) async {
    final ask = approver;
    if (ask == null) return false;
    try {
      return await ask(request);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Classification
  // ------------------------------------------------------------------

  /// The category a whole goal ("text Pratima hi") falls in, or null to read freely.
  static RiskCategory? classifyGoal(String goal) {
    final g = ' ${goal.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} '
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final rule in _goalRules) {
      if (!rule.$2.hasMatch(g)) continue;
      if (rule.$1 == RiskCategory.settings && _everydayControls.hasMatch(g)) return null;
      return rule.$1;
    }
    return null;
  }

  /// Torch, volume, brightness and playback are everyday controls, not settings.
  static final _everydayControls = RegExp(
      r' (?:flashlight|torch|volume|brightness|music|song|video|playback|alarm|timer|dark mode|night mode) ');

  /// The category of one agent step, judged by what it would actually touch:
  /// the label and view id of the button under a tap, or Enter in a messaging app.
  static RiskCategory? classifyStep(TaskStep step, List<ScreenNode> nodes) {
    switch (step.action) {
      case TaskStep.actionClickText:
        final text = step.stringParam('text') ?? '';
        final node = _nodeLabelled(text, nodes);
        return _classifyControl(text, node);
      case TaskStep.actionClickAt:
        final x = step.intParam('x'), y = step.intParam('y');
        if (x == null || y == null) return null;
        final node = _nodeAt(x, y, nodes);
        return node == null ? null : _classifyControl('', node);
      case TaskStep.actionPressEnter:
        return nodes.any((n) => _sendsOnEnter.contains(_package(n.viewId)))
            ? RiskCategory.send
            : null;
      default:
        return null;
    }
  }

  static RiskCategory? _classifyControl(String label, ScreenNode? node) {
    final labels = [label, node?.text ?? '', node?.contentDescription ?? '']
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty && l.length <= _maxControlLabel);
    for (final l in labels) {
      for (final rule in _controlRules) {
        if (rule.$2.hasMatch(l)) return rule.$1;
      }
    }
    final id = (node?.viewId ?? '').split('/').last.toLowerCase();
    for (final rule in _viewIdRules) {
      if (rule.$2.hasMatch(id)) return rule.$1;
    }
    return null;
  }

  /// Button labels are short; a long text is a paragraph that merely mentions "send".
  static const _maxControlLabel = 32;

  static ScreenNode? _nodeLabelled(String text, List<ScreenNode> nodes) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final n in nodes) {
      if (n.text.toLowerCase() == t || n.contentDescription.toLowerCase() == t) return n;
    }
    for (final n in nodes) {
      if (n.text.toLowerCase().contains(t) || n.contentDescription.toLowerCase().contains(t)) {
        return n;
      }
    }
    return null;
  }

  /// The smallest node under (x, y): the control itself, not its container.
  static ScreenNode? _nodeAt(int x, int y, List<ScreenNode> nodes) {
    ScreenNode? best;
    var bestArea = 1 << 62;
    for (final n in nodes) {
      if (x < n.left || x > n.right || y < n.top || y > n.bottom) continue;
      final area = (n.right - n.left) * (n.bottom - n.top);
      if (area < bestArea) {
        best = n;
        bestArea = area;
      }
    }
    return best;
  }

  static String _package(String viewId) {
    final i = viewId.indexOf(':');
    return i < 0 ? '' : viewId.substring(0, i);
  }

  /// Apps where Enter in the compose box sends the message.
  static const _sendsOnEnter = {
    'com.whatsapp',
    'com.whatsapp.w4b',
    'org.telegram.messenger',
    'com.google.android.apps.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
    'com.coloros.mms',
    'com.instagram.android',
    'com.facebook.orca',
    'com.snapchat.android',
    'com.discord',
    'com.Slack',
    'com.google.android.gm',
    'com.microsoft.teams',
    'com.linkedin.android',
    'com.twitter.android',
  };

  /// An act word only counts as the verb: at the start, or after a joiner
  /// ("open WhatsApp and message Mom", "can you call Mom"), so "read the last
  /// message" or "show my order history" stay free.
  static RegExp _verb(String words) => RegExp(
      r'(?:^ | (?:and|then|please|pls|to|you|also|now|just) )(?:' + words + r') ');

  // Order matters: the first match wins, so money is checked before "send".
  static final _goalRules = <(RiskCategory, RegExp)>[
    (RiskCategory.pay, _verb(r'pay|send money|transfer|buy|purchase|order|checkout|recharge|donate|subscribe to')),
    (RiskCategory.call, _verb(r'call|dial|ring|video call|voice call|facetime')),
    (RiskCategory.send, _verb(r'send|text|message|msg|sms|whatsapp|email|mail|reply|post|tweet|share|forward|comment|dm')),
    (RiskCategory.delete, _verb(r'delete|remove|erase|wipe|clear|uninstall|factory reset|archive|unsubscribe')),
    (RiskCategory.install, _verb(r'install|reinstall|download (?:the )?(?:\w+ )?app|update (?:the )?(?:\w+ )?apps?')),
    (RiskCategory.power, _verb(r'restart|reboot|shut down|shutdown|power off|sign out|log out|logout')),
    (RiskCategory.settings, _verb(r'turn on|turn off|switch on|switch off|enable|disable|grant|revoke|change|set up|connect|disconnect|forget|reset')),
  ];

  static RegExp _whole(String words) => RegExp('^(?:$words)\$');

  static final _controlRules = <(RiskCategory, RegExp)>[
    (RiskCategory.pay, _whole(r'pay|pay now|pay \S+|proceed to pay|confirm payment|buy|buy now|place order|place your order|checkout|proceed to checkout|subscribe|confirm order|transfer|send money|recharge')),
    (RiskCategory.call, _whole(r'call|voice call|video call|call \S+|dial')),
    (RiskCategory.send, _whole(r'send|send message|post|share|reply|publish|submit|tweet|forward|comment|send sms|send email')),
    (RiskCategory.delete, _whole(r'delete|delete \S+|remove|remove \S+|uninstall|erase|clear data|clear storage|clear all|reset|factory reset|archive|move to bin|move to trash')),
    (RiskCategory.install, _whole(r'install|update|install update|get|accept install')),
    (RiskCategory.power, _whole(r'restart|power off|shut down|reboot|sign out|log out')),
    (RiskCategory.settings, _whole(r'allow|allow all|while using the app|only this time|grant|turn on|turn off|enable|disable')),
  ];

  static final _viewIdRules = <(RiskCategory, RegExp)>[
    (RiskCategory.pay, RegExp(r'(?:^|_)(?:pay|payment|buy|checkout|place_order)(?:_|$)')),
    (RiskCategory.call, RegExp(r'(?:^|_)(?:call|dial|voip)(?:_|$)')),
    (RiskCategory.send, RegExp(r'(?:^|_)(?:send|post|share|submit)(?:_|$)')),
    (RiskCategory.delete, RegExp(r'(?:^|_)(?:delete|remove|uninstall|trash)(?:_|$)')),
    (RiskCategory.install, RegExp(r'(?:^|_)install(?:_|$)')),
  ];
}
