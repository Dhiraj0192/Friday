import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One model Friday can download and run on the phone. Sizes and sha256 are
/// Hugging Face's own LFS records for that exact file (checked 2026-11-08).
@immutable
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.repo,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.license,
    required this.note,
  });

  final String id;
  final String name;
  final String repo;
  final String file;
  final int bytes;
  final String sha256;
  final String license;
  final String note;

  Uri get url => Uri.parse('https://huggingface.co/$repo/resolve/main/$file');

  /// Roughly what it needs in RAM to run: the weights plus context and runtime.
  double get ramGb => bytes / (1 << 30) + 0.6;

  String get sizeLabel => '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
}

/// Ungated GGUF builds at Q4_K_M, smallest first. All run on CPU on a
/// Snapdragon 695 class phone; the larger ones are slow at driving apps.
const modelCatalogue = <ModelSpec>[
  ModelSpec(
    id: 'qwen2.5-0.5b',
    name: 'Qwen 2.5 0.5B',
    repo: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
    file: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    bytes: 491400032,
    sha256: '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
    license: 'Apache 2.0',
    note: 'Fastest; simple questions and short commands.',
  ),
  ModelSpec(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B',
    repo: 'unsloth/gemma-3-1b-it-GGUF',
    file: 'gemma-3-1b-it-Q4_K_M.gguf',
    bytes: 806058272,
    sha256: '8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd',
    license: 'Gemma terms',
    note: 'Fast, good plain chat.',
  ),
  ModelSpec(
    id: 'llama3.2-1b',
    name: 'Llama 3.2 1B',
    repo: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    file: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    bytes: 807694464,
    sha256: '6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83',
    license: 'Llama 3.2 licence',
    note: 'Fast, follows instructions well for its size.',
  ),
  ModelSpec(
    id: 'qwen3-1.7b',
    name: 'Qwen 3 1.7B',
    repo: 'unsloth/Qwen3-1.7B-GGUF',
    file: 'Qwen3-1.7B-Q4_K_M.gguf',
    bytes: 1107409472,
    sha256: 'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
    license: 'Apache 2.0',
    note: 'Recommended balance of speed and sense.',
  ),
  ModelSpec(
    id: 'qwen2.5-1.5b',
    name: 'Qwen 2.5 1.5B',
    repo: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
    file: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    bytes: 1117320736,
    sha256: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    license: 'Apache 2.0',
    note: 'Good at JSON, so steadier at driving apps.',
  ),
  ModelSpec(
    id: 'llama3.2-3b',
    name: 'Llama 3.2 3B',
    repo: 'bartowski/Llama-3.2-3B-Instruct-GGUF',
    file: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    bytes: 2019377696,
    sha256: '6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff',
    license: 'Llama 3.2 licence',
    note: 'Smarter, about a third the speed.',
  ),
  ModelSpec(
    id: 'qwen3-4b-2507',
    name: 'Qwen 3 4B Instruct',
    repo: 'unsloth/Qwen3-4B-Instruct-2507-GGUF',
    file: 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    bytes: 2497281120,
    sha256: '3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597',
    license: 'Apache 2.0',
    note: 'Best answers that fit; slow.',
  ),
];

class ModelStoreException implements Exception {
  const ModelStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Free app storage and whether the network is unmetered.
typedef StorageProbe = Future<({int freeBytes, bool unmetered})> Function();

/// Downloads, checks and keeps the on-phone models; one of them is active.
class ModelStore extends ChangeNotifier {
  ModelStore({
    http.Client Function()? client,
    Future<Directory> Function()? directory,
    StorageProbe? storage,
    this.catalogue = modelCatalogue,
  })  : _client = client ?? http.Client.new,
        _directory = directory ?? _defaultDirectory,
        _storage = storage ?? _defaultStorage;

  static final ModelStore instance = ModelStore();

  static const _activeKey = 'on_device_model';
  static const _wifiOnlyKey = 'on_device_wifi_only';
  static const _speedKey = 'on_device_speed_';

  /// Room kept free beyond the model itself, so the phone is not filled to the brim.
  static const headroomBytes = 1 << 30;

  final http.Client Function() _client;
  final Future<Directory> Function() _directory;
  final StorageProbe _storage;

  /// The models this store can download and make active.
  final List<ModelSpec> catalogue;

  /// Model id -> fraction downloaded, while a download runs.
  final progress = <String, double>{};
  final _cancelled = <String>{};

  ModelSpec? byId(String? id) {
    for (final spec in catalogue) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  Future<File> fileFor(ModelSpec spec) async => File('${(await _directory()).path}/${spec.file}');

  Future<bool> isDownloaded(ModelSpec spec) async {
    final file = await fileFor(spec);
    return await file.exists() && await file.length() == spec.bytes;
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<ModelSpec?> active() async => byId((await _prefs).getString(_activeKey));

  /// The active model's file, when it is downloaded; else null.
  Future<File?> activeFile() async {
    final spec = await active();
    if (spec == null || !await isDownloaded(spec)) return null;
    return fileFor(spec);
  }

  Future<void> setActive(ModelSpec? spec) async {
    final prefs = await _prefs;
    if (spec == null) {
      await prefs.remove(_activeKey);
    } else {
      if (!await isDownloaded(spec)) throw ModelStoreException('${spec.name} is not downloaded yet.');
      await prefs.setString(_activeKey, spec.id);
    }
    notifyListeners();
  }

  Future<bool> get wifiOnly async => (await _prefs).getBool(_wifiOnlyKey) ?? true;
  Future<void> setWifiOnly(bool value) async {
    await (await _prefs).setBool(_wifiOnlyKey, value);
    notifyListeners();
  }

  /// Pieces per second measured on this phone, once benchmarked.
  Future<double?> speed(ModelSpec spec) async => (await _prefs).getDouble('$_speedKey${spec.id}');
  Future<void> setSpeed(ModelSpec spec, double value) async {
    await (await _prefs).setDouble('$_speedKey${spec.id}', value);
    notifyListeners();
  }

  void cancel(ModelSpec spec) => _cancelled.add(spec.id);

  /// Downloads [spec], resuming a partial file, and checks its sha256 before
  /// it can be used. Throws [ModelStoreException] with a reason Sir can read.
  Future<void> download(ModelSpec spec) async {
    if (progress.containsKey(spec.id)) return;
    if (await isDownloaded(spec)) return;
    final target = await fileFor(spec);
    final part = File('${target.path}.part');
    var have = await part.exists() ? await part.length() : 0;
    if (have > spec.bytes) {
      await part.delete();
      have = 0;
    }

    final probe = await _storage();
    if (await wifiOnly && !probe.unmetered) {
      throw const ModelStoreException('Not on Wi-Fi. Connect to Wi-Fi, or allow mobile data in this screen.');
    }
    final need = spec.bytes - have + headroomBytes;
    if (probe.freeBytes < need) {
      throw ModelStoreException('Not enough room: ${spec.name} needs '
          '${(need / (1 << 30)).toStringAsFixed(1)} GB free, the phone has '
          '${(probe.freeBytes / (1 << 30)).toStringAsFixed(1)} GB.');
    }

    _cancelled.remove(spec.id);
    progress[spec.id] = have / spec.bytes;
    notifyListeners();
    final client = _client();
    try {
      await part.parent.create(recursive: true);
      final request = http.Request('GET', spec.url);
      if (have > 0) request.headers['range'] = 'bytes=$have-';
      final res = await client.send(request);
      if (res.statusCode == 200 && have > 0) {
        have = 0; // the server ignored the range: start over
      } else if (res.statusCode != 200 && res.statusCode != 206) {
        throw ModelStoreException('Hugging Face answered ${res.statusCode}.');
      }
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var lastShown = 0.0;
      try {
        await for (final chunk in res.stream) {
          if (_cancelled.contains(spec.id)) throw const ModelStoreException('Download cancelled.');
          sink.add(chunk);
          have += chunk.length;
          final shown = have / spec.bytes;
          if (shown - lastShown >= 0.005) {
            lastShown = shown;
            progress[spec.id] = shown;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (have != spec.bytes) {
        throw ModelStoreException('The download stopped early; tap download again to resume.');
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != spec.sha256) {
        await part.delete();
        throw const ModelStoreException('The file failed its checksum and was deleted. Download it again.');
      }
      await part.rename(target.path);
    } on ModelStoreException {
      rethrow;
    } on Exception catch (e) {
      throw ModelStoreException('The download broke off ($e); tap download again to resume.');
    } finally {
      client.close();
      progress.remove(spec.id);
      _cancelled.remove(spec.id);
      notifyListeners();
    }
  }

  /// Deletes the model and any partial download; clears it if it was active.
  Future<void> delete(ModelSpec spec) async {
    final target = await fileFor(spec);
    for (final f in [target, File('${target.path}.part')]) {
      if (await f.exists()) await f.delete();
    }
    if ((await active())?.id == spec.id) await setActive(null);
    notifyListeners();
  }

  static Future<Directory> _defaultDirectory() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
    await dir.create(recursive: true);
    return dir;
  }

  static const _channel = MethodChannel('com.privateagent/accessibility');

  static Future<({int freeBytes, bool unmetered})> _defaultStorage() async {
    final info = await _channel.invokeMapMethod<String, Object?>('modelStorage') ?? const {};
    return (
      freeBytes: (info['freeBytes'] as num?)?.toInt() ?? 0,
      unmetered: info['unmetered'] == true,
    );
  }
}
