import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/brain_router.dart';
import 'package:private_agent/services/friday_profile.dart';
import 'package:private_agent/services/model_store.dart';

final _payload = utf8.encode('GGUF' * 1000);

ModelSpec _spec({String? digest}) => ModelSpec(
      id: 'tiny',
      name: 'Tiny',
      repo: 'test/tiny',
      file: 'tiny.gguf',
      bytes: _payload.length,
      sha256: digest ?? sha256.convert(_payload).toString(),
      license: 'test',
      note: 'test',
    );

/// Serves [_payload], honouring Range; [cutAt] drops the connection there once.
class Hub {
  Hub({this.cutAt});
  int? cutAt;
  final ranges = <String?>[];

  late final client = MockClient.streaming((request, _) async {
    ranges.add(request.headers['range']);
    final start = int.tryParse(
            RegExp(r'bytes=(\d+)-').firstMatch(request.headers['range'] ?? '')?.group(1) ?? '') ??
        0;
    final body = _payload.sublist(start);
    final cut = cutAt;
    cutAt = null;
    final stream = cut == null
        ? Stream.value(body)
        : Stream<List<int>>.fromIterable([body.sublist(0, cut - start)])
            .followedBy(Stream.error(const SocketException('connection reset')));
    return http.StreamedResponse(stream, start > 0 ? 206 : 200);
  });
}

extension<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('models');
  });
  tearDown(() => dir.delete(recursive: true));

  ModelStore store(Hub hub, {int free = 1 << 40, bool wifi = true}) => ModelStore(
        client: () => hub.client,
        directory: () async => dir,
        storage: () async => (freeBytes: free, unmetered: wifi),
      );

  group('model store', () {
    test('the catalogue is real Hugging Face files with full hashes', () {
      expect(modelCatalogue.map((m) => m.id).toSet().length, modelCatalogue.length);
      for (final m in modelCatalogue) {
        expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: m.id);
        expect(m.url.toString(), startsWith('https://huggingface.co/${m.repo}/resolve/main/'));
        expect(m.file.toLowerCase(), endsWith('.gguf'));
      }
    });

    test('a broken download resumes from where it stopped and is checked', () async {
      final hub = Hub(cutAt: 1500);
      final models = store(hub);
      final spec = _spec();
      await expectLater(models.download(spec), throwsA(isA<ModelStoreException>()));
      expect(await models.isDownloaded(spec), isFalse);

      await models.download(spec);
      expect(hub.ranges, [null, 'bytes=1500-']);
      expect(await (await models.fileFor(spec)).readAsBytes(), _payload);
      expect(models.progress, isEmpty);

      await models.setActive(spec);
      expect((await models.activeFile())?.path, endsWith('tiny.gguf'));
      await models.delete(spec);
      expect(await models.active(), isNull);
    });

    test('a file that fails its checksum is thrown away', () async {
      final models = store(Hub());
      final spec = _spec(digest: '0' * 64);
      await expectLater(models.download(spec),
          throwsA(predicate((e) => e.toString().contains('checksum'))));
      expect(dir.listSync(), isEmpty);
    });

    test('refuses mobile data when Wi-Fi only, and a phone without room', () async {
      final spec = _spec();
      await expectLater(store(Hub(), wifi: false).download(spec),
          throwsA(predicate((e) => e.toString().contains('Wi-Fi'))));
      await expectLater(store(Hub(), free: 1000).download(spec),
          throwsA(predicate((e) => e.toString().contains('Not enough room'))));
      final mobile = store(Hub(), wifi: false);
      await mobile.setWifiOnly(false);
      await mobile.download(spec);
      expect(await mobile.isDownloaded(spec), isTrue);
    });

    test('a model cannot be made active before it is downloaded', () async {
      expect(() => store(Hub()).setActive(_spec()), throwsA(isA<ModelStoreException>()));
    });
  });

  group('brain router', () {
    test('falls back for no network and server trouble, not for a refused key', () {
      expect(BrainRouter.fallsBack(null), isTrue);
      expect(BrainRouter.fallsBack(502), isTrue);
      expect(BrainRouter.fallsBack(429), isTrue);
      expect(BrainRouter.fallsBack(401), isFalse);
      expect(BrainRouter.fallsBack(400), isFalse);
    });

    test('answers from the phone model with the system prompt and turns', () async {
      final seen = <Object>[];
      final router = BrainRouter(
        activeModel: () async => File('/models/tiny.gguf'),
        load: (path) async => seen.add(path),
        generate: (system, turns, maxTokens, temperature) {
          seen.addAll([system, turns, maxTokens]);
          return Stream.fromIterable(['<th', 'ink>hmm, battery', '</think>\n', 'Battery ', 'is 81%.']);
        },
      );
      final answer = await router.local([
        {'role': 'system', 'content': 'Be Friday.'},
        {'role': 'user', 'content': 'Battery?'},
        {'role': 'assistant', 'content': 'Checking.'},
      ], maxTokens: 4096, fallback: true);
      expect(answer, 'Battery is 81%.');
      expect(seen, [
        '/models/tiny.gguf',
        'Be Friday.',
        [(true, 'Battery?'), (false, 'Checking.')],
        BrainRouter.maxLocalTokens,
      ]);
      expect(router.offline.value, isTrue);
      router.remoteAnswered();
      expect(router.offline.value, isFalse);
    });

    test('says plainly when no model is ready, and will not take images', () async {
      final none = BrainRouter(activeModel: () async => null);
      expect(await none.hasLocal, isFalse);
      await expectLater(none.local([{'role': 'user', 'content': 'hi'}]),
          throwsA(predicate((e) => e.toString().contains('On-phone models'))));
      expect(BrainRouter.split([
        {'role': 'user', 'content': [{'type': 'image_url'}]},
      ]), isNull);
    });

    test('plain answers pass through untouched', () async {
      final out = await BrainRouter.withoutThinking(Stream.fromIterable(['Y', 'es.'])).join();
      expect(out, 'Yes.');
    });
  });

  test('her profile says what her offline brain is', () {
    String build(String? model) => FridayProfile.build(
        provider: 'jarvis_laptop', model: 'auto', maxSteps: 15, accessibility: true, offlineModel: model);
    expect(build(null), contains('no on-phone model'));
    expect(build('Qwen 3 1.7B'), contains('answers with Qwen 3 1.7B on the phone'));
  });
}
