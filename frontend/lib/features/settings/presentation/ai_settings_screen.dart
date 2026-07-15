import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/network/openrouter_service.dart';

/// AI configuration: pick a provider (OpenRouter / OpenAI / Anthropic /
/// Perplexity / custom-local), paste that provider's key, choose a model, and
/// Test. Everything is stored encrypted on-device, per provider.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();

  late String _provider = AppSettings.instance.providerId;
  late String _modelChoice;
  bool _keySet = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  AiProviderDef get _def => AppConfig.providerById(_provider);

  @override
  void initState() {
    super.initState();
    _syncFromSettings();
  }

  void _syncFromSettings() {
    final s = AppSettings.instance;
    _provider = s.providerId;
    _endpointCtrl.text = s.customEndpoint;
    final model = s.aiModel;
    final inList = _def.models.any((m) => m.$1 == model);
    _modelChoice = inList ? model : '__custom__';
    if (!inList) _modelCtrl.text = model;
    s.hasApiKey().then((v) {
      if (mounted) setState(() => _keySet = v);
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _endpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _onProviderChanged(String id) async {
    await AppSettings.instance.setProvider(id);
    _keyCtrl.clear();
    if (mounted) setState(_syncFromSettings);
  }

  Future<void> _save() async {
    final s = AppSettings.instance;
    await s.setProvider(_provider);
    if (_provider == AppConfig.providerCustom) {
      await s.setCustomEndpoint(_endpointCtrl.text);
    }
    if (_keyCtrl.text.trim().isNotEmpty) {
      await s.setApiKey(_keyCtrl.text);
      _keyCtrl.clear();
    }
    final model = (_modelChoice == '__custom__') ? _modelCtrl.text : _modelChoice;
    await s.setAiModel(model);
    final set = await s.hasApiKey();
    if (mounted) {
      setState(() => _keySet = set);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI settings saved on this device')));
    }
  }

  Future<void> _removeKey() async {
    await AppSettings.instance.setApiKey('');
    if (mounted) {
      setState(() => _keySet = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API key removed')));
    }
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final svc = OpenRouterService();
      final reply = await svc.ask(prompt: 'Reply with the single word: OK');
      final via = svc.lastModelUsed;
      setState(() {
        _testOk = true;
        _testResult = 'Success! AI replied: "${reply.trim()}"'
            '${via != null ? '\nModel used: $via' : ''}';
      });
    } on OpenRouterException catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.message;
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCustom = _provider == AppConfig.providerCustom;
    final needsKey = _def.needsKey;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'File tools work offline. AI features use the provider you pick '
                  'below with your own key. OpenRouter is easiest — one key, every model.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Provider
          _sectionTitle('Provider', Icons.hub_outlined),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provider,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: AppConfig.providers
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.label, overflow: TextOverflow.ellipsis, maxLines: 1),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) _onProviderChanged(v);
            },
          ),
          const SizedBox(height: 16),

          // API key (only if provider needs one)
          if (needsKey) ...[
            _sectionTitle('API Key', Icons.key,
                trailing: _keySet ? _badge('Set', Colors.green) : null),
            const SizedBox(height: 8),
            TextField(
              controller: _keyCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _keySet ? 'Replace key (leave blank to keep)' : 'Paste your ${_def.label.split(' ').first} key',
                prefixIcon: const Icon(Icons.vpn_key, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_def.keysUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Get a key at ${_def.keysUrl}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
            if (_keySet)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _removeKey,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove key'),
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Custom endpoint (only for custom provider)
          if (isCustom) ...[
            _sectionTitle('Server URL', Icons.dns_outlined),
            const SizedBox(height: 8),
            TextField(
              controller: _endpointCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'OpenAI-compatible endpoint',
                hintText: 'http://192.168.1.10:1234/v1/chat/completions',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            Text('Point to a local server (Ollama, LM Studio) on your Wi-Fi for offline AI.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
          ],

          // Model
          _sectionTitle('Model', Icons.smart_toy_outlined),
          const SizedBox(height: 8),
          if (_def.models.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _modelChoice,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [
                ..._def.models.map((m) => DropdownMenuItem(
                      value: m.$1,
                      child: Text(m.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                    )),
                const DropdownMenuItem(value: '__custom__', child: Text('Custom model…')),
              ],
              onChanged: (v) => setState(() => _modelChoice = v ?? _modelChoice),
            ),
          if (_def.models.isEmpty || _modelChoice == '__custom__') ...[
            if (_def.models.isNotEmpty) const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model name',
                hintText: 'e.g. llama3, gpt-4o, claude-3-5-haiku-latest',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Tip: pick a vision model to read images/PDFs. If one is busy or gone, '
            'switch model or provider.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? 'Testing…' : 'Test'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
          ]),

          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testOk ? Colors.green : cs.error).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(_testOk ? Icons.check_circle : Icons.error_outline,
                    color: _testOk ? Colors.green : cs.error, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_testResult!, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, {Widget? trailing}) => Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const Spacer(),
        if (trailing != null) trailing,
      ]);

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}
