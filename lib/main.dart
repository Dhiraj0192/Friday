import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app.dart';
import 'overlay/overlay_app.dart';
import 'services/bus_service.dart';
import 'services/calendar_reminder_service.dart';
import 'services/hermes_evolution_service.dart';
import 'services/jarvis_service.dart';
import 'services/native_bridge_service.dart';
import 'services/sentry_service.dart';
import 'services/settings_service.dart';
import 'services/task_executor.dart';
import 'services/todo_service.dart';
import 'services/risk_approval.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridgeService.instance.init();

  final settings = SettingsService.instance;
  await settings.init();

  final executor = TaskExecutor.instance;
  await executor.init();
  RiskApproval.install();
  BusService.instance.start();

  await HermesEvolutionService.instance.init();
  await CalendarReminderService.instance.init();
  await TodoService.instance.init();

  if (settings.jarvisAlwaysOn) {
    JarvisService.instance.ensureAlwaysOnRunning();
  }

  _wireOverlayCommands(executor);

  runApp(const PrivateAgentApp());
}

/// Commands coming from the floating overlay bubble/panel.
void _wireOverlayCommands(TaskExecutor executor) {
  FlutterOverlayWindow.overlayListener.listen((event) async {
    if (event is! String) return;
    Map<String, dynamic> decoded;
    try {
      final d = jsonDecode(event);
      if (d is! Map) return;
      decoded = d.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return;
    }
    if (decoded['type'] != 'command') return;
    switch (decoded['command']) {
      case 'start':
        final goal = decoded['goal']?.toString().trim() ?? '';
        if (goal.isNotEmpty && !executor.isBusy) {
          unawaited(executor.executeTask(goal));
        }
        break;
      case 'pause':
        executor.pause();
        break;
      case 'resume':
        executor.resume();
        break;
      case 'cancel':
        executor.cancel();
        break;
      case 'summarize_screen':
        unawaited(JarvisService.instance.processCommand('summarize this screen article'));
        break;
      case 'jarvis_command':
        final goal = decoded['goal']?.toString().trim() ?? '';
        if (goal.isNotEmpty) {
          unawaited(JarvisService.instance.processCommand(goal));
        }
        break;
      case 'toggle_sentry':
        unawaited(SentryService.instance.toggleSentry());
        break;
    }
  });
}

/// Entry point for the floating overlay window (separate Flutter engine
/// running in its own isolate). Must stay a top-level function annotated
/// with vm:entry-point.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}
