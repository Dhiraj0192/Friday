import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import 'risk_gate.dart';
import 'screen_automation_service.dart';
import 'system_control_service.dart';

/// Asks Sir on the phone: Friday comes to the front with an Allow / Deny
/// dialog and a heads-up notification, then steps back to the app she was
/// driving. No answer within [timeout] is a no.
class RiskApproval {
  RiskApproval._();

  static const timeout = Duration(seconds: 60);

  static void install() => RiskGate.approver = ask;

  static Future<bool> ask(RiskRequest request) async {
    final wasInFront =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final screen = ScreenAutomationService.instance;
    unawaited(SystemControlService.instance
        .notify('Friday needs your yes, Sir', request.prompt));
    if (!wasInFront) {
      try {
        await screen.bringToFront();
      } catch (_) {}
    }
    final yes = await _dialog(request).timeout(timeout, onTimeout: () {
      final nav = PrivateAgentApp.navigatorKey.currentState;
      if (nav != null && nav.canPop()) nav.pop(false);
      return false;
    });
    if (!wasInFront) {
      try {
        await screen.moveToBack();
      } catch (_) {}
    }
    return yes;
  }

  static Future<bool> _dialog(RiskRequest request) async {
    // The activity may still be coming forward; give the navigator a moment.
    NavigatorState? nav;
    for (var i = 0; i < 20 && nav == null; i++) {
      nav = PrivateAgentApp.navigatorKey.currentState;
      if (nav == null) await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (nav == null || !nav.context.mounted) return false;
    final answer = await showDialog<bool>(
      context: nav.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Allow this, Sir?'),
        content: Text(request.prompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }
}
