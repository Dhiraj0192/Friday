import 'package:flutter_test/flutter_test.dart';

import 'package:private_agent/models/screen_node.dart';
import 'package:private_agent/models/task_step.dart';
import 'package:private_agent/services/risk_gate.dart';

ScreenNode node(String text,
    {String desc = '', String id = '', int l = 0, int t = 0, int r = 100, int b = 100}) {
  return ScreenNode(
    index: 0,
    text: text,
    contentDescription: desc,
    className: 'android.widget.Button',
    viewId: id,
    isClickable: true,
    isEditable: false,
    isScrollable: false,
    isCheckable: false,
    isEnabled: true,
    left: l,
    top: t,
    right: r,
    bottom: b,
    centerX: (l + r) ~/ 2,
    centerY: (t + b) ~/ 2,
  );
}

TaskStep tap(String text) =>
    TaskStep(action: TaskStep.actionClickText, params: {'text': text});

void main() {
  tearDown(() {
    RiskGate.approver = null;
    RiskGate.verifier = null;
  });

  group('classifyGoal', () {
    final cases = <String, RiskCategory?>{
      'text Pratima hi': RiskCategory.send,
      'open WhatsApp and message Mom I am late': RiskCategory.send,
      'can you call Mom': RiskCategory.call,
      'send money to Ravi on GPay': RiskCategory.pay,
      'pay the electricity bill': RiskCategory.pay,
      'delete the screenshots from today': RiskCategory.delete,
      'install Spotify': RiskCategory.install,
      'restart the phone': RiskCategory.power,
      'turn on Bluetooth': RiskCategory.settings,
      // Reading, opening and everyday controls stay free.
      'read the last message from Pratima': null,
      'show my order history': null,
      'open YouTube': null,
      'what is my battery level': null,
      'turn on the flashlight': null,
      'turn off the alarm': null,
      'search for pizza near me': null,
    };
    cases.forEach((goal, expected) {
      test('"$goal" -> ${expected?.name ?? 'free'}', () {
        expect(RiskGate.classifyGoal(goal), expected);
      });
    });
  });

  group('classifyStep', () {
    test('tapping a Send button is send; a paragraph mentioning send is not', () {
      const paragraph = 'Tap below to send the files you picked to your friends';
      final nodes = [node('Send'), node(paragraph)];
      expect(RiskGate.classifyStep(tap('Send'), nodes), RiskCategory.send);
      expect(RiskGate.classifyStep(tap(paragraph), nodes), isNull);
    });

    test('click_at judges the smallest control under the point, by view id too', () {
      final nodes = [
        node('', r: 1000, b: 2000, id: 'com.whatsapp:id/conversation'),
        node('', l: 900, t: 1800, r: 1000, b: 1900, id: 'com.whatsapp:id/send'),
      ];
      expect(
          RiskGate.classifyStep(
              const TaskStep(action: TaskStep.actionClickAt, params: {'x': 950, 'y': 1850}), nodes),
          RiskCategory.send);
      expect(
          RiskGate.classifyStep(
              const TaskStep(action: TaskStep.actionClickAt, params: {'x': 100, 'y': 100}), nodes),
          isNull);
    });

    test('Pay and Delete buttons are caught by label', () {
      final nodes = [node('Pay ₹500'), node('Delete')];
      expect(RiskGate.classifyStep(tap('Pay ₹500'), nodes), RiskCategory.pay);
      expect(RiskGate.classifyStep(tap('Delete'), nodes), RiskCategory.delete);
    });

    test('Enter sends in a messaging app, not elsewhere', () {
      const enter = TaskStep(action: TaskStep.actionPressEnter);
      expect(RiskGate.classifyStep(enter, [node('', id: 'com.whatsapp:id/entry')]),
          RiskCategory.send);
      expect(RiskGate.classifyStep(enter, [node('', id: 'com.android.chrome:id/url_bar')]),
          isNull);
    });

    test('typing and scrolling are free', () {
      expect(
          RiskGate.classifyStep(
              const TaskStep(action: TaskStep.actionTypeText, params: {'text': 'send'}),
              [node('Send')]),
          isNull);
      expect(RiskGate.classifyStep(const TaskStep(action: TaskStep.actionScroll), const []),
          isNull);
    });
  });

  group('approve', () {
    const req = RiskRequest(category: RiskCategory.send, what: 'text Pratima hi', origin: 'jarvis');

    test('fails closed with no approver installed', () async {
      expect(await RiskGate.approve(req), isFalse);
    });

    test('fails closed when the approver throws', () async {
      RiskGate.approver = (_) async => throw StateError('no screen');
      expect(await RiskGate.approve(req), isFalse);
    });

    test('passes the answer through and names who asked', () async {
      RiskRequest? seen;
      RiskGate.approver = (r) async {
        seen = r;
        return true;
      };
      expect(await RiskGate.approve(req), isTrue);
      expect(seen!.prompt,
          'A request from Jarvis would send or post something: "text Pratima hi". Allow it?');
      expect(const RiskRequest(category: RiskCategory.call, what: 'call Mom').prompt,
          startsWith('This would place a call'));
    });
  });

  group('fingerprint', () {
    const pay = RiskRequest(category: RiskCategory.pay, what: 'pay 500 to Ravi');

    test('only money, deletion and power need it', () {
      expect(RiskCategory.values.where((c) => c.isHighRisk).toSet(),
          {RiskCategory.pay, RiskCategory.delete, RiskCategory.power});
    });

    test('other acts pass without asking for it', () async {
      var asked = false;
      RiskGate.verifier = (_) async => asked = true;
      expect(await RiskGate.verify(const RiskRequest(category: RiskCategory.send, what: 'x')), isTrue);
      expect(asked, isFalse);
    });

    test('fails closed with no check, a failed check, or one that throws', () async {
      expect(await RiskGate.verify(pay), isFalse);
      RiskGate.verifier = (_) async => false;
      expect(await RiskGate.verify(pay), isFalse);
      RiskGate.verifier = (_) async => throw StateError('no fingerprint enrolled');
      expect(await RiskGate.verify(pay), isFalse);
      RiskGate.verifier = (_) async => true;
      expect(await RiskGate.verify(pay), isTrue);
    });
  });
}
