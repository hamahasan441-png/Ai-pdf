import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/network/openrouter_service.dart';

/// Dedicated, easy-to-find screen for AI configuration:
///   - API key (OpenRouter) — stored encrypted on device
///   - Model picker (curated free models + custom)
///   - Endpoint: online (OpenRouter) or custom/offline (local LAN server)
///   - Test button to verify the setup actually works
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController(text: AppSettings.instance.aiModel);
  final _endpointCtrl = TextEditingController(text: AppSettings.instance.aiEndpoint);

  late String _modelChoice = AppConfig.aiModels.any((m) => m.$1 == AppSettings.instance.aiModel)
      ? AppSettings.instance.aiModel
      : '__custom__';
  late bool _customEndpoint = !AppSettings.instance.isOpenRouterEndpoint;
  bool _keySet = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.hasOpenRouterKey().then((v) {
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

  Future<void> _save() async {
    if (_keyCtrl.text.trim().isNotEmpty) {
      await AppSettings.instance.setOpenRouterKey(_keyCtrl.text);
      _keyCtrl.clear();
    }
    await AppSettings.instance
        .setAiModel(_modelChoice == '__custom__' ? _modelCtrl.text : _modelChoice);
    await AppSettings.instance
        .setAiEndpoint(_customEndpoint ? _endpointCtrl.text : AppConfig.openRouterUrl);
    _endpointCtrl.text = AppSettings.instance.aiEndpoint;
    final set = await AppSettings.instance.hasOpenRouterKey();
    if (mounted) {
      setState(() => _keySet = set);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI settings saved on this device')));
    }
  }

  Future<void> _removeKey() async {
    await AppSettings.instance.setOpenRouterKey('');
    if (mounted) {
      setState(() => _keySet = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI key removed')));
    }
  }

  Future<void> _test() async {
    await _save(); // persist current values first
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await OpenRouterService().ask(prompt: 'Reply with the single word: OK');
      setState(() {
        _testOk = true;
        _testResult = 'Success! The AI replied: "${reply.trim()}"';
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
                  'File tools work fully offline. AI features (Understand, Fill Form) '
                  'need a key. Get a free one at openrouter.ai/keys.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // API key
          _sectionTitle('API Key', Icons.key, trailing: _keySet ? _badge('Set', Colors.green) : null),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _keySet ? 'Replace key (leave blank to keep)' : 'Paste OpenRouter key (sk-or-...)',
              prefixIcon: const Icon(Icons.vpn_key, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
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

          // Model
          _sectionTitle('Model', Icons.smart_toy_outlined),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _modelChoice,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [
              ...AppConfig.aiModels.map((m) => DropdownMenuItem(
                    value: m.$1,
                    child: Text(m.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                  )),
              const DropdownMenuItem(value: '__custom__', child: Text('Custom model…')),
            ],
            onChanged: (v) => setState(() => _modelChoice = v ?? _modelChoice),
          ),
          if (_modelChoice == '__custom__') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Custom model slug',
                hintText: 'provider/model:free',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Endpoint
          _sectionTitle('AI Source', Icons.dns_outlined),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('OpenRouter (online)'),
              selected: !_customEndpoint,
              onSelected: (_) => setState(() => _customEndpoint = false),
            ),
            ChoiceChip(
              label: const Text('Custom / offline'),
              selected: _customEndpoint,
              onSelected: (_) => setState(() => _customEndpoint = true),
            ),
          ]),
          if (_customEndpoint) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _endpointCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'AI endpoint (OpenAI-compatible)',
                hintText: 'http://192.168.1.10:1234/v1/chat/completions',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use a local server (Ollama, LM Studio) on your Wi-Fi for offline AI. '
              'No key needed if the server has none.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
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
