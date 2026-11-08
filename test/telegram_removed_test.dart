import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/settings_service.dart';

void main() {
  test('start-up deletes the removed Telegram bridge\'s saved token and chats',
      () async {
    SharedPreferences.setMockInitialValues({
      'telegram_enabled': true,
      'telegram_token': '123:secret',
      'telegram_allowed_chats': <String>['42'],
      'telegram_owner_chat': '42',
      'telegram_offset': 7,
      'agent_max_steps': 12,
    });

    await SettingsService.instance.init();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('telegram_')), isEmpty);
    expect(prefs.getInt('agent_max_steps'), 12, reason: 'other settings stay');
  });

  test('no Telegram code is left in the app', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('settings_service.dart'))
        // The Telegram app's package id may appear (Enter sends there).
        .where((f) => f
            .readAsStringSync()
            .toLowerCase()
            .replaceAll('org.telegram.messenger', '')
            .contains('telegram'))
        .map((f) => f.path);
    expect(hits, isEmpty);
  });
}
