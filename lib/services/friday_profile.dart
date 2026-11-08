import '../models/task_step.dart';
import 'risk_gate.dart';
import 'screen_automation_service.dart';
import 'settings_service.dart';

/// Friday's description of herself for Jarvis, built from her own code so it
/// cannot drift from what she actually does. Only verified abilities are
/// listed; the demo features (smart home, network audit, Sentry, Code Black)
/// are left out on purpose, so neither agent believes them.
class FridayProfile {
  FridayProfile._();

  static String build({
    required String provider,
    required String model,
    required int maxSteps,
    required bool accessibility,
  }) {
    final actions = TaskStep.supportedActions.join(', ');
    final asks = RiskCategory.values.map((c) => '- ${c.describe}').join('\n');
    return '''
# Friday

Friday is Sir's agent on his Android phone (OPPO F21s Pro). She reads the screen through
Android accessibility and drives apps the way a person would: open, tap, type, scroll.
She is not Jarvis and does not see the laptop, Sir's mail or his calendar except through
apps on the phone.

## Ask Friday for
- Anything inside a phone app: open it, find something in it, read what it shows.
- The phone's state: battery and charging, what is on screen, the time.
- Quick controls: torch, volume, brightness, media play/pause/next, alarms.
- Contacts, calls and messages (each needs Sir's yes on the phone).
- Installing an app from the Play Store (needs Sir's yes).

## How she works
- An agent loop of up to $maxSteps steps; each step is one of: $actions.
- Phrase a request to her as one task with a clear end; for a question, she answers
  in a sentence or two when she reaches done.
- Brain right now: $provider ($model). With no network she has no brain yet.
- Screen control (accessibility) is ${accessibility ? 'on' : 'OFF, so she cannot drive apps until Sir turns it back on'}.

## What needs Sir's yes on the phone, whoever asks
$asks
If Sir says no, she answers "Declined by Sir." Reading and opening things are free.

## Limits
- One task at a time: Jarvis's requests run in turn, and if she is in the middle of
  a task for Sir she answers that she is busy.
- She cannot see behind the lock screen, inside secure or banking screens that block
  accessibility, or read another app's private data.
- Messages from Jarvis reach her as requests, and her own safety gate still applies.
''';
  }

  /// Her profile as of now, from the live settings.
  static Future<String> current() async {
    final settings = SettingsService.instance;
    return build(
      provider: settings.provider,
      model: settings.model,
      maxSteps: settings.maxSteps,
      accessibility: await ScreenAutomationService.instance.isServiceEnabled(),
    );
  }
}
