import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'model_store.dart';
import 'on_device_llm.dart';

/// Picks Friday's brain for each request: the configured remote one (the
/// laptop's FreeLLMAPI, or a cloud provider) first, and the model on the phone
/// when that is out of reach. [offline] says which one answered last.
class BrainRouter {
  BrainRouter({
    Future<File?> Function()? activeModel,
    Future<void> Function(String path)? load,
    Stream<String> Function(String system, List<(bool, String)> turns, int maxTokens, double temperature)? generate,
  })  : _activeModel = activeModel ?? ModelStore.instance.activeFile,
        _load = load ?? ((path) => OnDeviceLlm.instance.load(path)),
        _generate = generate ??
            ((system, turns, maxTokens, temperature) => OnDeviceLlm.instance
                .chat(system, turns, maxTokens: maxTokens, temperature: temperature));

  static final BrainRouter instance = BrainRouter();

  /// Small models answer short; a long budget only adds wait on a phone CPU.
  static const maxLocalTokens = 512;

  /// What fits the phone model's 8K context with room left for the reply, at
  /// a cautious three characters a token.
  static const maxLocalChars = 20000;

  final Future<File?> Function() _activeModel;
  final Future<void> Function(String path) _load;
  final Stream<String> Function(String, List<(bool, String)>, int, double) _generate;

  /// True while the phone's own model is answering because the remote one is out of reach.
  final offline = ValueNotifier<bool>(false);

  /// Whether a remote failure should go to the phone's model: no network, a
  /// timeout, or the server failing; never a refused key or a bad request.
  static bool fallsBack(int? statusCode) =>
      statusCode == null || statusCode == 429 || statusCode >= 500;

  Future<bool> get hasLocal async => await _activeModel() != null;

  void remoteAnswered() => offline.value = false;

  /// OpenAI-style messages as one system prompt and the turns after it, or
  /// null when a message is not plain text (an image), which the phone cannot read.
  static (String, List<(bool, String)>)? split(List<Map<String, dynamic>> messages) {
    final system = <String>[];
    final turns = <(bool, String)>[];
    for (final m in messages) {
      final content = m['content'];
      if (content is! String) return null;
      switch (m['role']) {
        case 'system':
          system.add(content);
        case 'assistant':
          turns.add((false, content));
        default:
          turns.add((true, content));
      }
    }
    return (system.join('\n\n'), turns);
  }

  /// [turns] cut to fit beside [system] in [budget] characters: the oldest go
  /// first, the kept ones start with Sir's, and only then is the last one cut.
  static List<(bool, String)> fit(String system, List<(bool, String)> turns, {int budget = maxLocalChars}) {
    final kept = List.of(turns);
    int size() => kept.fold(system.length, (n, t) => n + t.$2.length);
    while (kept.length > 1 && (size() > budget || !kept.first.$1)) {
      kept.removeAt(0);
    }
    if (kept.isNotEmpty && size() > budget) {
      final last = kept.removeLast();
      kept.add((last.$1, last.$2.substring(0, max(0, budget - system.length))));
    }
    return kept;
  }

  /// Streams the phone model's answer to [messages]; [fallback] marks it as offline mode.
  Stream<String> localStream(
    List<Map<String, dynamic>> messages, {
    int maxTokens = maxLocalTokens,
    double temperature = 0.4,
    bool fallback = false,
  }) async* {
    final file = await _activeModel();
    if (file == null) {
      throw const LocalBrainException(
          'No on-phone model is ready. Download one in Settings > On-phone models and set it active.');
    }
    final parts = split(messages);
    if (parts == null) throw const LocalBrainException('The on-phone model cannot read images.');
    final turns = fit(parts.$1, parts.$2);
    await _load(file.path);
    offline.value = fallback;
    yield* withoutThinking(_generate(parts.$1, turns, maxTokens.clamp(16, maxLocalTokens), temperature));
  }

  /// Drops a leading `<think>...</think>` block (Qwen 3 thinks aloud first).
  static Stream<String> withoutThinking(Stream<String> pieces) async* {
    var head = '';
    var passing = false;
    await for (final piece in pieces) {
      if (passing) {
        yield piece;
        continue;
      }
      head += piece;
      final trimmed = head.trimLeft();
      if (trimmed.length < 7 && '<think>'.startsWith(trimmed)) continue;
      if (!trimmed.startsWith('<think>')) {
        passing = true;
        yield head;
        continue;
      }
      final end = head.indexOf('</think>');
      if (end == -1) continue;
      passing = true;
      final rest = head.substring(end + 8).trimLeft();
      if (rest.isNotEmpty) yield rest;
    }
  }

  Future<String> local(List<Map<String, dynamic>> messages,
          {int maxTokens = maxLocalTokens, double temperature = 0.4, bool fallback = false}) =>
      localStream(messages, maxTokens: maxTokens, temperature: temperature, fallback: fallback).join();
}

class LocalBrainException implements Exception {
  const LocalBrainException(this.message);
  final String message;
  @override
  String toString() => message;
}
