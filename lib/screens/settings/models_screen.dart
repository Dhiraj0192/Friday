import 'package:flutter/material.dart';

import '../../services/model_store.dart';
import '../../services/on_device_llm.dart';
import '../../services/settings_service.dart';
import '../../widgets/glass_widgets.dart';

/// Download, test and choose the model Friday runs on the phone itself.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final _store = ModelStore.instance;
  final _downloaded = <String>{};
  final _speeds = <String, double>{};
  String? _activeId;
  bool _wifiOnly = true;
  String? _benchmarking;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final downloaded = <String>{};
    final speeds = <String, double>{};
    for (final spec in modelCatalogue) {
      if (await _store.isDownloaded(spec)) downloaded.add(spec.id);
      final speed = await _store.speed(spec);
      if (speed != null) speeds[spec.id] = speed;
    }
    final active = await _store.active();
    final wifiOnly = await _store.wifiOnly;
    if (!mounted) return;
    setState(() {
      _downloaded
        ..clear()
        ..addAll(downloaded);
      _speeds
        ..clear()
        ..addAll(speeds);
      _activeId = active?.id;
      _wifiOnly = wifiOnly;
    });
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _download(ModelSpec spec) async {
    try {
      await _store.download(spec);
      _say('${spec.name} is downloaded and checked.');
    } on ModelStoreException catch (e) {
      _say(e.message);
    }
  }

  Future<void> _benchmark(ModelSpec spec) async {
    setState(() => _benchmarking = spec.id);
    try {
      await OnDeviceLlm.instance.load((await _store.fileFor(spec)).path);
      final speed = await OnDeviceLlm.instance.benchmark();
      await _store.setSpeed(spec, speed);
      _say('${spec.name}: about ${speed.toStringAsFixed(1)} pieces a second on this phone.');
    } catch (e) {
      _say('The test failed: $e');
    } finally {
      if (mounted) setState(() => _benchmarking = null);
    }
  }

  Future<void> _delete(ModelSpec spec) async {
    if (OnDeviceLlm.instance.loadedPath == (await _store.fileFor(spec)).path) {
      await OnDeviceLlm.instance.unload();
    }
    await _store.delete(spec);
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScaffold(
      appBar: AppBar(title: const Text('On-phone models'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Friday answers with the laptop\'s brain when it is reachable, and with the model '
            'set active here when it is not. Pick "On this phone" as the provider to use it always. '
            'Small models chat well; driving apps is slower and less sure than with the laptop.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          GlassSwitchTile(
            title: 'Download on Wi-Fi only',
            subtitle: 'Models are 0.5 to 2.5 GB',
            icon: Icons.wifi_rounded,
            value: _wifiOnly,
            onChanged: (v) => _store.setWifiOnly(v),
          ),
          if (SettingsService.instance.provider != 'on_device' && _activeId != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Offline fallback is ready.', style: TextStyle(fontSize: 12, color: Colors.green)),
            ),
          for (final spec in modelCatalogue) _card(spec),
        ],
      ),
    );
  }

  Widget _card(ModelSpec spec) {
    final have = _downloaded.contains(spec.id);
    final active = _activeId == spec.id;
    final progress = _store.progress[spec.id];
    final speed = _speeds[spec.id];
    return GlassCard(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      borderColor: active ? const Color(0xFF6366F1) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(spec.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
            if (active) const Chip(label: Text('Active'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 4),
          Text(
            '${spec.sizeLabel} · needs about ${spec.ramGb.toStringAsFixed(1)} GB RAM · ${spec.license}'
            '${speed == null ? '' : ' · ${speed.toStringAsFixed(1)}/s here'}',
            style: const TextStyle(fontSize: 11.5),
          ),
          Text(spec.note, style: const TextStyle(fontSize: 12)),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            if (progress != null)
              TextButton(onPressed: () => _store.cancel(spec), child: const Text('Cancel'))
            else if (!have)
              TextButton(onPressed: () => _download(spec), child: const Text('Download'))
            else ...[
              if (!active)
                TextButton(onPressed: () => _store.setActive(spec), child: const Text('Set active')),
              TextButton(
                onPressed: _benchmarking == null ? () => _benchmark(spec) : null,
                child: Text(_benchmarking == spec.id ? 'Testing…' : 'Test speed'),
              ),
              TextButton(onPressed: () => _delete(spec), child: const Text('Delete')),
            ],
          ]),
        ],
      ),
    );
  }
}
