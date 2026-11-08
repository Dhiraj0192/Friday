import 'dart:async';

import 'package:llamadart/llamadart.dart';

/// The model that runs on the phone itself (llama.cpp through llamadart), for
/// when the laptop's brain is out of reach. One model is loaded at a time.
class OnDeviceLlm {
  OnDeviceLlm._();
  static final OnDeviceLlm instance = OnDeviceLlm._();

  static const defaultContext = 4096;

  LlamaEngine? _engine;
  String? _loadedPath;

  bool get isLoaded => _engine != null;
  String? get loadedPath => _loadedPath;

  /// Loads the GGUF at [path]; a no-op when it is already the loaded one.
  Future<void> load(String path, {int contextSize = defaultContext}) async {
    if (_engine != null && _loadedPath == path) return;
    await unload();
    _engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(path)),
      params: ModelParams(contextSize: contextSize, gpuLayers: 0),
    );
    _loadedPath = path;
  }

  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _loadedPath = null;
    await engine?.dispose();
  }

  /// Streams the reply to [turns] (oldest first; true = Sir) under [system].
  Stream<String> chat(
    String system,
    List<(bool, String)> turns, {
    int maxTokens = 512,
    double temperature = 0.4,
  }) async* {
    final engine = _engine;
    if (engine == null) throw StateError('no on-phone model is loaded');
    final messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
      for (final (isSir, text) in turns)
        LlamaChatMessage.fromText(
          role: isSir ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: text,
        ),
    ];
    await for (final chunk in engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: temperature),
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  void stop() => _engine?.cancelGeneration();

  /// Rough speed on this phone: pieces streamed per second for a short reply.
  Future<double> benchmark() async {
    final watch = Stopwatch()..start();
    var pieces = 0;
    await for (final _ in chat('Answer briefly.', const [(true, 'Count from one to thirty in words.')],
        maxTokens: 96, temperature: 0)) {
      pieces++;
    }
    watch.stop();
    return watch.elapsedMilliseconds == 0 ? 0 : pieces * 1000 / watch.elapsedMilliseconds;
  }
}
