import 'dart:ui';
import 'package:flutter/material.dart';

import '../../services/bus_service.dart';
import '../../services/personality_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/glass_widgets.dart';
import 'jarvis_settings_screen.dart';
import 'permissions_screen.dart';

/// Next-Generation Liquid Glass Settings Screen.
/// Clean, executive grouped hierarchy with frosted glass translucency and modern controls.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;

  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  final _pairController = TextEditingController();
  String? _pairError;

  bool _obscureKey = true;

  String _lastSyncedProvider = '';

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: _settings.baseUrl);
    _apiKeyController = TextEditingController(text: _settings.apiKey);
    _modelController = TextEditingController(text: _settings.model);
    _lastSyncedProvider = _settings.provider;

    PersonalityService.instance.init().then((_) {
      if (mounted) setState(() {});
    });

    for (final c in [
      _baseUrlController,
      _apiKeyController,
      _modelController,
    ]) {
      c.addListener(_onAiFieldChanged);
    }
    _settings.addListener(_onSettingsChanged);
    PersonalityService.instance.addListener(_onServiceChanged);
    BusService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    PersonalityService.instance.removeListener(_onServiceChanged);
    BusService.instance.removeListener(_onServiceChanged);
    _pairController.dispose();
    for (final c in [
      _baseUrlController,
      _apiKeyController,
      _modelController,
    ]) {
      c.removeListener(_onAiFieldChanged);
    }
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (_settings.provider != _lastSyncedProvider) {
      _lastSyncedProvider = _settings.provider;
      _baseUrlController.text = _settings.baseUrl;
      _modelController.text = _settings.model;
    }
    setState(() {});
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onAiFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _aiDirty =>
      _baseUrlController.text.trim() != _settings.baseUrl ||
      _apiKeyController.text.trim() != _settings.apiKey ||
      _modelController.text.trim() != _settings.model;

  Future<void> _saveAiSettings() async {
    await _settings.setBaseUrl(_baseUrlController.text);
    await _settings.setApiKey(_apiKeyController.text);
    await _settings.setModel(_modelController.text);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('AI provider settings saved successfully'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0x60090E17)
                  : const Color(0x60F1F5F9),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Ambient background glow
          Positioned(
            top: 40,
            right: -40,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                _sectionHeader(
                  icon: Icons.psychology_rounded,
                  title: 'AI Intelligence Engine',
                  color: const Color(0xFF818CF8),
                ),
                _aiProviderCard(),
                const SizedBox(height: 22),

                _sectionHeader(
                  icon: Icons.shield_rounded,
                  title: 'Autonomous Friday Core',
                  color: const Color(0xFF00E5FF),
                ),
                _jarvisCard(),
                const SizedBox(height: 22),

                _sectionHeader(
                  icon: Icons.hub_rounded,
                  title: 'Jarvis Link',
                  color: const Color(0xFFF59E0B),
                ),
                _jarvisLinkCard(),
                const SizedBox(height: 22),

                _sectionHeader(
                  icon: Icons.security_rounded,
                  title: 'Permissions & Telemetry Inboxes',
                  color: const Color(0xFF38BDF8),
                ),
                _permissionsCard(),
                const SizedBox(height: 22),

                _sectionHeader(
                  icon: Icons.smart_toy_rounded,
                  title: 'Device Automation Agent',
                  color: const Color(0xFFA78BFA),
                ),
                _agentCard(),
                const SizedBox(height: 22),

                _sectionHeader(
                  icon: Icons.palette_outlined,
                  title: 'Appearance & Visual Theme',
                  color: const Color(0xFFF472B6),
                ),
                _appearanceCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiProviderCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Model Provider Preset',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in SettingsService.providers.entries)
                GlassPill(
                  label: entry.value.label,
                  isSelected: _settings.provider == entry.key,
                  onTap: () => _settings.setProvider(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 18),
          GlassTextField(
            controller: _baseUrlController,
            labelText: 'Base URL',
            hintText: 'https://api.example.com/v1',
            prefixIcon: const Icon(Icons.link_rounded, size: 20),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _apiKeyController,
            labelText: 'API key',
            obscureText: _obscureKey,
            prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _modelController,
            labelText: 'Model',
            hintText: 'deepseek-chat',
            prefixIcon: const Icon(Icons.psychology_outlined, size: 20),
          ),
          const SizedBox(height: 16),
          // Save button with liquid glass styling
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _aiDirty ? _saveAiSettings : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _aiDirty
                    ? const Color(0xFF6366F1)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: _aiDirty ? 4 : 0,
              ),
              icon: Icon(
                _aiDirty ? Icons.save_rounded : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(
                _aiDirty ? 'Save changes' : 'Saved',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
          ),
          if (_aiDirty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'Unsaved changes — tap Save to persist your API key and model.',
                  style: TextStyle(fontSize: 11.5, color: Colors.amber),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          GlassSwitchTile(
            title: 'Send system prompt',
            subtitle: 'Recommended — teaches model precise phone action schema',
            icon: Icons.code_rounded,
            value: _settings.useSystemPrompt,
            onChanged: (v) => _settings.setUseSystemPrompt(v),
          ),
          const SizedBox(height: 6),
          GlassSliderRow(
            label: 'Temperature (Creativity)',
            value: _settings.temperature,
            min: 0,
            max: 2,
            divisions: 20,
            displayValue: _settings.temperature.toStringAsFixed(1),
            onChanged: (v) => _settings.setTemperature(v),
          ),
          GlassSliderRow(
            label: 'Max Response Tokens',
            value: _settings.maxTokens.toDouble(),
            min: 256,
            max: 4096,
            divisions: 15,
            displayValue: _settings.maxTokens.toString(),
            onChanged: (v) => _settings.setMaxTokens(v.round()),
          ),
        ],
      ),
    );
  }

  Widget _jarvisCard() {
    final theme = Theme.of(context);
    final isAlwaysOn = _settings.jarvisAlwaysOn;
    final persona = PersonalityService.instance.archetype.name.toUpperCase();
    final voice = _settings.jarvisNeuralVoice.split('-').length > 2
        ? _settings.jarvisNeuralVoice.split('-')[2].replaceAll('Neural', '')
        : 'Ryan';

    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const JarvisSettingsScreen()),
              )
              .then((_) => setState(() {}));
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF00E5FF).withValues(alpha: 0.35),
                          const Color(0xFF00E5FF).withValues(alpha: 0.08),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF00E5FF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'FRIDAY',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: isAlwaysOn
                                    ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isAlwaysOn
                                      ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
                                      : theme.colorScheme.outline.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isAlwaysOn ? 'ALWAYS-ON ACTIVE' : 'STANDBY',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isAlwaysOn
                                      ? const Color(0xFF00E5FF)
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Always-on ears, studio neural voice, personality, workflows & memory',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF00E5FF),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GlassPill(
                    icon: const Icon(Icons.mic_rounded, size: 13, color: Color(0xFF00E5FF)),
                    label: isAlwaysOn ? 'Hands-Free Receptors' : 'Tap to Talk',
                    color: const Color(0xFF00E5FF),
                  ),
                  GlassPill(
                    icon: const Icon(Icons.record_voice_over_rounded, size: 13, color: Color(0xFFFFD700)),
                    label: '$voice Studio Voice',
                    color: const Color(0xFFFFD700),
                  ),
                  GlassPill(
                    icon: const Icon(Icons.psychology_outlined, size: 13, color: Color(0xFFBA68C8)),
                    label: '$persona Tone',
                    color: const Color(0xFFBA68C8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pairJarvis() async {
    try {
      final link = BusCodec.decodePairing(_pairController.text);
      await _settings.setJarvisLink(link.url.toString(), link.token);
      _pairController.clear();
      setState(() => _pairError = null);
      BusService.instance.restart();
    } on FormatException catch (e) {
      setState(() => _pairError = e.message);
    }
  }

  Future<void> _unpairJarvis() async {
    BusService.instance.stop();
    await _settings.clearJarvisLink();
  }

  String _busStatusText() {
    final bus = BusService.instance;
    if (!_settings.isJarvisPaired) return 'Not paired. On the laptop run: server.py pair-friday';
    if (!_settings.jarvisLinkEnabled) return 'Switched off. Jarvis cannot reach Friday.';
    final where = Uri.tryParse(_settings.jarvisBusUrl)?.host ?? '';
    return switch (bus.state) {
      BusState.online => bus.jarvisRunning ? 'Connected to Jarvis · $where' : 'Laptop reached; Jarvis is not running',
      BusState.connecting => 'Connecting to $where…',
      BusState.offline => bus.lastError ?? 'Out of reach; retrying',
      BusState.off => 'Idle',
    };
  }

  Widget _jarvisLinkCard() {
    final paired = _settings.isJarvisPaired;
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _busStatusText(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          if (paired) ...[
            GlassSwitchTile(
              title: 'Jarvis link',
              subtitle: 'Jarvis may ask Friday to read and open things; acting still needs your yes',
              icon: Icons.hub_rounded,
              value: _settings.jarvisLinkEnabled,
              onChanged: (v) async {
                await _settings.setJarvisLinkEnabled(v);
                BusService.instance.restart();
              },
            ),
            TextButton.icon(
              onPressed: _unpairJarvis,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: const Text('Unpair'),
            ),
          ] else ...[
            GlassTextField(
              controller: _pairController,
              labelText: 'Pairing code',
              hintText: 'friday1:…',
              prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
              keyboardType: TextInputType.visiblePassword,
            ),
            if (_pairError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _pairError!,
                  style: const TextStyle(fontSize: 11.5, color: Colors.amber),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pairJarvis,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Pair with Jarvis'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionsCard() {
    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PermissionsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: Color(0xFF38BDF8),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'App Permissions & Inboxes',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Microphone, SMS stream, Email inbox & Accessibility service',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GlassPill(
                    icon: Icon(Icons.sms_outlined, size: 13, color: Colors.blueAccent),
                    label: 'SMS Inbox',
                    color: Colors.blueAccent,
                  ),
                  GlassPill(
                    icon: Icon(Icons.mark_email_unread_outlined, size: 13, color: Colors.amber),
                    label: 'Email Stream',
                    color: Colors.amber,
                  ),
                  GlassPill(
                    icon: Icon(Icons.mic_rounded, size: 13, color: Color(0xFF00E5FF)),
                    label: 'Mic Receptor',
                    color: Color(0xFF00E5FF),
                  ),
                  GlassPill(
                    icon: Icon(Icons.accessibility_new_rounded, size: 13, color: Color(0xFF818CF8)),
                    label: 'Screen Touch',
                    color: Color(0xFF818CF8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          GlassSliderRow(
            label: 'Maximum Task Steps',
            value: _settings.maxSteps.toDouble(),
            min: 3,
            max: 40,
            divisions: 37,
            displayValue: '${_settings.maxSteps} steps',
            onChanged: (v) => _settings.setMaxSteps(v.round()),
          ),
          GlassSliderRow(
            label: 'Step Delay Buffer',
            value: _settings.stepDelayMs.toDouble(),
            min: 200,
            max: 5000,
            divisions: 24,
            displayValue: '${(_settings.stepDelayMs / 1000).toStringAsFixed(1)}s',
            onChanged: (v) => _settings.setStepDelayMs(v.round()),
          ),
          const SizedBox(height: 4),
          GlassSwitchTile(
            title: 'Skill Memory (Macro Fast Replay)',
            subtitle: 'Replay known sequences without invoking AI model',
            icon: Icons.auto_awesome_rounded,
            value: _settings.skillsEnabled,
            onChanged: (v) => _settings.setSkillsEnabled(v),
          ),
          GlassSwitchTile(
            title: 'Spoken Voice Feedback',
            subtitle: 'Vocalize automation progress and task results aloud',
            icon: Icons.record_voice_over_rounded,
            value: _settings.voiceFeedback,
            onChanged: (v) => _settings.setVoiceFeedback(v),
          ),
        ],
      ),
    );
  }

  Widget _appearanceCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Theme Preference',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.system,
                  label: 'System',
                  icon: Icons.brightness_auto_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.light,
                  label: 'Light',
                  icon: Icons.light_mode_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.dark,
                  label: 'Dark',
                  icon: Icons.dark_mode_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeOption({
    required ThemeMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _settings.themeMode == mode;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _settings.setThemeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.10),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
