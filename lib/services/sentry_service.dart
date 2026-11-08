import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'personality_service.dart';
import 'system_control_service.dart';
import 'voice_service.dart';

/// Tactical Sentry Mode Anti-Theft Watchdog:
/// Uses device motion sensors to detect unauthorized phone handling,
/// captures silent front-camera telemetry, alerts the room,
/// and raises a local notification with the time of the breach.
class SentryService extends ChangeNotifier {
  SentryService._();
  static final SentryService instance = SentryService._();

  static const MethodChannel _channel = MethodChannel('com.privateagent/accessibility');

  bool _isArmed = false;
  bool get isArmed => _isArmed;

  bool _breachDetected = false;
  bool get breachDetected => _breachDetected;

  String? _lastBreachPhotoBase64;
  String? get lastBreachPhotoBase64 => _lastBreachPhotoBase64;

  DateTime? _lastBreachTime;
  DateTime? get lastBreachTime => _lastBreachTime;

  /// Handles incoming native sentry call dispatched by [NativeBridgeService].
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method == 'onSentryMovementDetected') {
      final args = call.arguments as Map?;
      final b64 = args?['base64']?.toString() ?? '';
      await _handleBreach(b64);
    }
  }

  Future<bool> armSentry() async {
    try {
      final success = await _channel.invokeMethod<bool>('startSentryMode') ?? false;
      _isArmed = success;
      _breachDetected = false;
      notifyListeners();

      if (success) {
        final msg = PersonalityService.instance.getSentryAck(arm: true);
        await VoiceService.instance.speak(msg);
      }
      return success;
    } catch (e) {
      debugPrint('[SentryService] Arm failed: $e');
      _isArmed = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> disarmSentry() async {
    try {
      await _channel.invokeMethod('stopSentryMode');
    } catch (e) {
      debugPrint('[SentryService] stopSentryMode channel warning: $e');
    }
    _isArmed = false;
    _breachDetected = false;
    notifyListeners();

    final msg = PersonalityService.instance.getSentryAck(arm: false);
    await VoiceService.instance.speak(msg);
    return true;
  }

  Future<void> toggleSentry() async {
    if (_isArmed) {
      await disarmSentry();
    } else {
      await armSentry();
    }
  }

  Future<void> _handleBreach(String photoBase64) async {
    if (!_isArmed) return;
    _breachDetected = true;
    _lastBreachPhotoBase64 = photoBase64.isNotEmpty ? photoBase64 : null;
    _lastBreachTime = DateTime.now();
    notifyListeners();

    HapticFeedback.heavyImpact();

    // 1. Imposing vocal deterrence
    const alertSpeech = 'Security violation detected. Spatial coordinates and facial telemetry logged and dispatched.';
    unawaited(VoiceService.instance.speak(alertSpeech));

    // 2. Local notification; the snapshot stays in the app (lastBreachPhoto).
    final timeFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    await SystemControlService.instance.notify(
      'Friday sentry alert',
      'Unauthorized movement at $timeFormatted. Snapshot saved in the app.',
    );
  }
}

