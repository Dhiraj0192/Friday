import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start-up moves an API key from plain prefs into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'ai_api_key': 'sk-old-plain',
      'smart_home_ha_token': 'ha-old-plain',
    });
    FlutterSecureStorage.setMockInitialValues({});

    await SettingsService.instance.init();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('ai_api_key'), isFalse, reason: 'no plain copy left');
    expect(prefs.containsKey('smart_home_ha_token'), isFalse);
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'ai_api_key'), 'sk-old-plain');
    expect(SettingsService.instance.apiKey, 'sk-old-plain');
    expect(SettingsService.instance.homeAssistantToken, 'ha-old-plain');
  });

  test('a new key is written to secure storage, never to prefs', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService.instance.init();

    await SettingsService.instance.setApiKey('  sk-new  ');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.contains('key') || k.contains('token')), isEmpty);
    expect(await const FlutterSecureStorage().read(key: 'ai_api_key'), 'sk-new');
    expect(SettingsService.instance.apiKey, 'sk-new');
  });
}
