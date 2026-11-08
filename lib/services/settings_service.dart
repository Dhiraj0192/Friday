import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interaction mode of the home screen.
///
/// - [agent]: agent mode — tasks are executed on the device via the
///   observe → think → act loop (accessibility service required).
/// - [chat]: plain chatbot mode — messages get a conversational LLM reply,
///   no screen reading and no device actions.
/// - [jarvis]: JARVIS mode — hands-free voice-first autonomous agent & assistant
///   with live holographic Iron Man HUD animation, intelligent action/chat routing,
///   and full device control.
enum AppMode { agent, chat, jarvis }

/// Visual HUD display style for JARVIS mode.
///
/// - [arcReactor]: Arc Reactor (3D spherical consciousness core with gyroscopic armillary rings).
/// - [jarvis]: Jarvis (3D Iron Man hologram suit avatar with reactive telemetry).
enum JarvisScreenStyle { arcReactor, jarvis }

/// Central, observable store for all user-configurable settings.
///
/// Backed by SharedPreferences, except secrets (API key, tokens), which live in
/// the Android Keystore via flutter_secure_storage and are cached in memory so
/// reads stay synchronous. Access via [SettingsService.instance] after calling
/// [init] once at app start.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;
  static const _secure = FlutterSecureStorage();
  final Map<String, String> _secrets = {};

  bool get isReady => _prefs != null;

  /// Keys whose values are secrets. Older versions kept them in plain prefs.
  static const _secretKeys = ['ai_api_key', 'smart_home_ha_token', 'jarvis_bus_token'];

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Ensure system prompt is enabled so models always receive the agent action grammar
    if (_prefs?.getBool('ai_use_system_prompt') != true) {
      await _prefs?.setBool('ai_use_system_prompt', true);
    }
    // The Telegram bridge was removed; drop its saved bot token and chats.
    for (final key in _removedTelegramKeys) {
      await _prefs?.remove(key);
    }
    await _loadSecrets();
  }

  /// Loads secrets from secure storage, moving any left in plain prefs there.
  /// A plain copy is removed only once the secure write succeeded.
  Future<void> _loadSecrets() async {
    for (final key in _secretKeys) {
      try {
        final plain = _prefs?.getString(key);
        if (plain != null) {
          await _secure.write(key: key, value: plain);
          await _prefs?.remove(key);
        }
        final value = await _secure.read(key: key);
        if (value != null) _secrets[key] = value;
      } catch (e) {
        debugPrint('Secure storage unavailable for $key: $e');
        final plain = _prefs?.getString(key);
        if (plain != null) _secrets[key] = plain;
      }
    }
  }

  String _secret(String key) => _secrets[key] ?? '';

  Future<void> _setSecret(String key, String value) async {
    _secrets[key] = value;
    await _secure.write(key: key, value: value);
  }

  static const _removedTelegramKeys = [
    'telegram_enabled',
    'telegram_token',
    'telegram_allowed_chats',
    'telegram_owner_chat',
    'telegram_offset',
  ];

  // ------------------------------------------------------------------
  // AI provider
  // ------------------------------------------------------------------

  /// Well-known OpenAI-compatible providers.
  static const Map<String, ({String label, String baseUrl, String model})>
  providers = {
    'deepseek': (
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ),
    'openai': (
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
    ),
    'gemini': (
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.0-flash',
    ),
    'openrouter': (
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
    ),
    'nvidia': (
      label: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.3-70b-instruct',
    ),
    // Through the paired laptop: FreeLLMAPI, with the laptop's key (the URL
    // comes from the Jarvis pairing, so baseUrl here stays empty).
    'jarvis_laptop': (label: 'Jarvis laptop (FreeLLMAPI)', baseUrl: '', model: 'auto'),
    // The model downloaded to the phone itself (Settings > On-phone models).
    'on_device': (label: 'On this phone (offline)', baseUrl: '', model: 'gguf'),
    'ollama': (
      label: 'Ollama (local)',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'llama3.2',
    ),
    'custom': (label: 'Custom (OpenAI-compatible)', baseUrl: '', model: ''),
  };

  String get provider => _prefs?.getString('ai_provider') ?? 'deepseek';
  Future<void> setProvider(String value) async {
    await _prefs?.setString('ai_provider', value);
    final preset = providers[value];
    if (preset != null && (preset.baseUrl.isNotEmpty || preset.model.isNotEmpty)) {
      await _prefs?.setString('ai_base_url', preset.baseUrl);
      await _prefs?.setString('ai_model', preset.model);
    }
    notifyListeners();
  }

  String get baseUrl =>
      _prefs?.getString('ai_base_url') ??
      providers[provider]?.baseUrl ??
      providers['deepseek']!.baseUrl;
  Future<void> setBaseUrl(String value) async {
    await _prefs?.setString('ai_base_url', value.trim());
    notifyListeners();
  }

  String get apiKey => _secret('ai_api_key');
  Future<void> setApiKey(String value) async {
    await _setSecret('ai_api_key', value.trim());
    notifyListeners();
  }

  String get model =>
      _prefs?.getString('ai_model') ??
      providers[provider]?.model ??
      'deepseek-chat';
  Future<void> setModel(String value) async {
    await _prefs?.setString('ai_model', value.trim());
    notifyListeners();
  }

  /// Defaults to 2048 so reasoning models (which burn completion tokens on
  /// hidden thinking before answering) still have budget left for the reply.
  int get maxTokens => _prefs?.getInt('ai_max_tokens') ?? 2048;
  Future<void> setMaxTokens(int value) async {
    await _prefs?.setInt('ai_max_tokens', value.clamp(128, 16384));
    notifyListeners();
  }

  double get temperature => _prefs?.getDouble('ai_temperature') ?? 0.2;
  Future<void> setTemperature(double value) async {
    await _prefs?.setDouble('ai_temperature', value.clamp(0.0, 2.0));
    notifyListeners();
  }

  bool get useSystemPrompt => _prefs?.getBool('ai_use_system_prompt') ?? true;
  Future<void> setUseSystemPrompt(bool value) async {
    await _prefs?.setBool('ai_use_system_prompt', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Agent loop
  // ------------------------------------------------------------------

  int get maxSteps => _prefs?.getInt('agent_max_steps') ?? 15;
  Future<void> setMaxSteps(int value) async {
    await _prefs?.setInt('agent_max_steps', value.clamp(3, 40));
    notifyListeners();
  }

  /// Delay between loop iterations, lets the UI settle after each action.
  int get stepDelayMs => _prefs?.getInt('agent_step_delay_ms') ?? 1200;
  Future<void> setStepDelayMs(int value) async {
    await _prefs?.setInt('agent_step_delay_ms', value.clamp(200, 10000));
    notifyListeners();
  }

  bool get skillsEnabled => _prefs?.getBool('agent_skills_enabled') ?? true;
  Future<void> setSkillsEnabled(bool value) async {
    await _prefs?.setBool('agent_skills_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Interaction mode
  // ------------------------------------------------------------------

  /// Whether the home screen sends messages to the agent loop
  /// ([AppMode.agent]), treats them as plain conversation
  /// ([AppMode.chat]), or enters voice-first hands-free ([AppMode.jarvis]).
  AppMode get appMode {
    final raw = _prefs?.getString('ui_app_mode') ?? 'agent';
    if (raw == 'genie') return AppMode.agent;
    return AppMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppMode.agent,
    );
  }

  Future<void> setAppMode(AppMode mode) async {
    await _prefs?.setString('ui_app_mode', mode.name);
    notifyListeners();
  }

  // Appearance, voice & onboarding
  // ------------------------------------------------------------------

  /// Visual HUD display style for JARVIS mode.
  /// Options: [JarvisScreenStyle.arcReactor] ("Arc Reactor"), [JarvisScreenStyle.jarvis] ("Jarvis").
  JarvisScreenStyle get jarvisScreenStyle {
    final raw = _prefs?.getString('jarvis_screen_style') ?? 'arcReactor';
    return JarvisScreenStyle.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => JarvisScreenStyle.arcReactor,
    );
  }

  Future<void> setJarvisScreenStyle(JarvisScreenStyle value) async {
    await _prefs?.setString('jarvis_screen_style', value.name);
    notifyListeners();
  }

  /// Whether JARVIS listens continuously like Google Home without tapping.
  /// Whether Friday already asked once to be spared battery optimisation.
  bool get batteryExemptionAsked => _prefs?.getBool('battery_exemption_asked') ?? false;
  Future<void> setBatteryExemptionAsked() async {
    await _prefs?.setBool('battery_exemption_asked', true);
  }

  bool get jarvisAlwaysOn => _prefs?.getBool('jarvis_always_on') ?? true;
  Future<void> setJarvisAlwaysOn(bool value) async {
    await _prefs?.setBool('jarvis_always_on', value);
    notifyListeners();
  }

  /// Voice profile: 'paul' (British Jarvis), 'friday' (Irish), 'stark' (US), 'kip' (Deep), 'cortana' (Smooth).
  String get jarvisVoice => _prefs?.getString('jarvis_voice') ?? 'paul';
  Future<void> setJarvisVoice(String value) async {
    await _prefs?.setString('jarvis_voice', value);
    notifyListeners();
  }

  /// Studio Neural Voice (Edge-TTS) for ultra-realistic human speech.
  /// Defaults to en-GB-RyanNeural (Paul Bettany British JARVIS style).
  String get jarvisNeuralVoice =>
      _prefs?.getString('jarvis_neural_voice') ?? 'en-GB-RyanNeural';
  Future<void> setJarvisNeuralVoice(String value) async {
    await _prefs?.setString('jarvis_neural_voice', value);
    notifyListeners();
  }

  /// Whether to prioritize ultra-realistic neural human voices over offline TTS.
  bool get useNeuralVoice =>
      _prefs?.getBool('jarvis_use_neural_voice') ?? true;
  Future<void> setUseNeuralVoice(bool value) async {
    await _prefs?.setBool('jarvis_use_neural_voice', value);
    notifyListeners();
  }

  /// Self-evolving skills & workflows like Hermes Agent.
  bool get jarvisWorkflowsEnabled =>
      _prefs?.getBool('jarvis_workflows_enabled') ?? true;
  Future<void> setJarvisWorkflowsEnabled(bool value) async {
    await _prefs?.setBool('jarvis_workflows_enabled', value);
    notifyListeners();
  }

  /// Local-First Privacy Mode: answers only with the model downloaded to the
  /// phone, and speaks with the phone's own voice.
  bool get localFirstPrivacyMode =>
      _prefs?.getBool('local_first_privacy_mode') ?? false;
  Future<void> setLocalFirstPrivacyMode(bool value) async {
    await _prefs?.setBool('local_first_privacy_mode', value);
    if (value) {
      await setProvider('on_device');
      await setUseNeuralVoice(false);
    }
    notifyListeners();
  }

  /// Permission system: prompts for explicit confirmation before high-risk operations
  /// (e.g. sending messages, placing calls, deleting data, purchases).
  bool get confirmRiskyActions =>
      _prefs?.getBool('confirm_risky_actions') ?? true;
  Future<void> setConfirmRiskyActions(bool value) async {
    await _prefs?.setBool('confirm_risky_actions', value);
    notifyListeners();
  }

  ThemeMode get themeMode {
    final raw = _prefs?.getString('ui_theme_mode') ?? 'system';
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString('ui_theme_mode', mode.name);
    notifyListeners();
  }

  bool get onboardingComplete =>
      _prefs?.getBool('onboarding_complete') ?? false;
  Future<void> setOnboardingComplete(bool value) async {
    await _prefs?.setBool('onboarding_complete', value);
    notifyListeners();
  }

  /// Whether the assistant should speak results aloud via TTS.
  bool get voiceFeedback => _prefs?.getBool('voice_feedback') ?? false;
  Future<void> setVoiceFeedback(bool value) async {
    await _prefs?.setBool('voice_feedback', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Jarvis link: the bus to Jarvis on Sir's laptop (see BusService)
  // ------------------------------------------------------------------

  /// The laptop phone server's https://….ts.net address, from the pairing code.
  String get jarvisBusUrl => _prefs?.getString('jarvis_bus_url') ?? '';

  /// Friday's own bus token, revocable on the laptop apart from anything else.
  String get jarvisBusToken => _secret('jarvis_bus_token');

  bool get isJarvisPaired => jarvisBusUrl.isNotEmpty && jarvisBusToken.isNotEmpty;

  Future<void> setJarvisLink(String url, String token) async {
    await _setSecret('jarvis_bus_token', token);
    await _prefs?.setString('jarvis_bus_url', url);
    notifyListeners();
  }

  Future<void> clearJarvisLink() async {
    _secrets.remove('jarvis_bus_token');
    await _secure.delete(key: 'jarvis_bus_token');
    await _prefs?.remove('jarvis_bus_url');
    notifyListeners();
  }

  /// Kill switch: off, Friday neither listens to Jarvis nor sends to him.
  bool get jarvisLinkEnabled => _prefs?.getBool('jarvis_link_enabled') ?? true;
  Future<void> setJarvisLinkEnabled(bool value) async {
    await _prefs?.setBool('jarvis_link_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Advanced Features: Smart Home, Commute, Jarvis Eye, Macro Recorder
  // ------------------------------------------------------------------

  /// Smart Home / Home Assistant URL (e.g. http://192.168.1.100:8123)
  String get homeAssistantUrl =>
      _prefs?.getString('smart_home_ha_url') ?? 'http://homeassistant.local:8123';
  Future<void> setHomeAssistantUrl(String value) async {
    await _prefs?.setString('smart_home_ha_url', value.trim());
    notifyListeners();
  }

  /// Home Assistant Long-Lived Access Token
  String get homeAssistantToken => _secret('smart_home_ha_token');
  Future<void> setHomeAssistantToken(String value) async {
    await _setSecret('smart_home_ha_token', value.trim());
    notifyListeners();
  }

  /// Whether Smart Home integration is enabled
  bool get smartHomeEnabled =>
      _prefs?.getBool('smart_home_enabled') ?? true;
  Future<void> setSmartHomeEnabled(bool value) async {
    await _prefs?.setBool('smart_home_enabled', value);
    notifyListeners();
  }

  /// Default Smart Home entity ID (e.g. light.living_room)
  String get smartHomeDefaultEntity =>
      _prefs?.getString('smart_home_default_entity') ?? 'light.living_room';
  Future<void> setSmartHomeDefaultEntity(String value) async {
    await _prefs?.setString('smart_home_default_entity', value.trim());
    notifyListeners();
  }

  /// Commute: Home address / origin
  String get commuteHomeAddress =>
      _prefs?.getString('commute_home_address') ?? 'Downtown';
  Future<void> setCommuteHomeAddress(String value) async {
    await _prefs?.setString('commute_home_address', value.trim());
    notifyListeners();
  }

  /// Commute: Work / standard destination address
  String get commuteWorkAddress =>
      _prefs?.getString('commute_work_address') ?? 'Tech Park';
  Future<void> setCommuteWorkAddress(String value) async {
    await _prefs?.setString('commute_work_address', value.trim());
    notifyListeners();
  }

  /// Commute travel mode: 'driving', 'transit', 'walking', 'cycling'
  String get commuteMode =>
      _prefs?.getString('commute_mode') ?? 'driving';
  Future<void> setCommuteMode(String value) async {
    await _prefs?.setString('commute_mode', value);
    notifyListeners();
  }

  /// Proactive Commute & Traffic warnings before meetings
  bool get proactiveCommuteEnabled =>
      _prefs?.getBool('proactive_commute_enabled') ?? true;
  Future<void> setProactiveCommuteEnabled(bool value) async {
    await _prefs?.setBool('proactive_commute_enabled', value);
    notifyListeners();
  }

  /// Jarvis Eye Multimodal Camera Perception
  bool get jarvisEyeEnabled =>
      _prefs?.getBool('jarvis_eye_enabled') ?? true;
  Future<void> setJarvisEyeEnabled(bool value) async {
    await _prefs?.setBool('jarvis_eye_enabled', value);
    notifyListeners();
  }

  /// Autonomous Macro Recorder
  bool get macroRecorderEnabled =>
      _prefs?.getBool('macro_recorder_enabled') ?? true;
  Future<void> setMacroRecorderEnabled(bool value) async {
    await _prefs?.setBool('macro_recorder_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Autonomous Proactive Vocalization & Scheduled Nudges
  // ------------------------------------------------------------------

  /// Master switch: whether JARVIS can speak up proactively on its own
  bool get jarvisAutoSpeakEnabled =>
      _prefs?.getBool('jarvis_auto_speak_enabled') ?? true;
  Future<void> setJarvisAutoSpeakEnabled(bool value) async {
    await _prefs?.setBool('jarvis_auto_speak_enabled', value);
    notifyListeners();
  }

  /// Whether JARVIS automatically opens a hands-free confirmation window
  /// ("Yes" or "No") after asking a proactive question
  bool get proactiveVoiceConfirmationEnabled =>
      _prefs?.getBool('proactive_voice_confirmation_enabled') ?? true;
  Future<void> setProactiveVoiceConfirmationEnabled(bool value) async {
    await _prefs?.setBool('proactive_voice_confirmation_enabled', value);
    notifyListeners();
  }

  /// Proactive Bedtime / Night Mode prompt (around 9:30 PM - 11 PM)
  bool get proactiveNightModePrompt =>
      _prefs?.getBool('proactive_night_mode_prompt') ?? true;
  Future<void> setProactiveNightModePrompt(bool value) async {
    await _prefs?.setBool('proactive_night_mode_prompt', value);
    notifyListeners();
  }

  /// Proactive Morning Briefing prompt (around 7:30 AM - 9 AM)
  bool get proactiveMorningBriefingPrompt =>
      _prefs?.getBool('proactive_morning_briefing_prompt') ?? true;
  Future<void> setProactiveMorningBriefingPrompt(bool value) async {
    await _prefs?.setBool('proactive_morning_briefing_prompt', value);
    notifyListeners();
  }

  /// Proactive Study & Focus Protocol prompt (afternoon study session)
  bool get proactiveStudyPrompt =>
      _prefs?.getBool('proactive_study_prompt') ?? true;
  Future<void> setProactiveStudyPrompt(bool value) async {
    await _prefs?.setBool('proactive_study_prompt', value);
    notifyListeners();
  }

  /// Proactive Remaining Tasks Review (late afternoon agenda check)
  bool get proactiveTaskReminderPrompt =>
      _prefs?.getBool('proactive_task_reminder_prompt') ?? true;
  Future<void> setProactiveTaskReminderPrompt(bool value) async {
    await _prefs?.setBool('proactive_task_reminder_prompt', value);
    notifyListeners();
  }

  /// Proactive Upcoming Meeting Reminders (15-30m before calendar events)
  bool get proactiveMeetingReminders =>
      _prefs?.getBool('proactive_meeting_reminders') ?? true;
  Future<void> setProactiveMeetingReminders(bool value) async {
    await _prefs?.setBool('proactive_meeting_reminders', value);
    notifyListeners();
  }

  /// Proactive Low Battery Warning (< 20%)
  bool get proactiveBatteryAlert =>
      _prefs?.getBool('proactive_battery_alert') ?? true;
  Future<void> setProactiveBatteryAlert(bool value) async {
    await _prefs?.setBool('proactive_battery_alert', value);
    notifyListeners();
  }
}
