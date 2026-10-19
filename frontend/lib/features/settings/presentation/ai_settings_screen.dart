import 'package:flutter/material.dart';

import 'package:ai_pdf/core/utils/error_text.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/config/locale_controller.dart';
import '../../../core/network/openrouter_service.dart';
import '../../../core/theme/theme_controller.dart';

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
  final _serverCtrl = TextEditingController();

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
    _serverCtrl.text = s.apiBaseUrl;
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
    _serverCtrl.dispose();
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
    if (_provider == AppConfig.providerManaged) {
      await s.setApiBaseUrl(_serverCtrl.text);
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
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.aSettingsSaved)));
    }
  }

  Future<void> _removeKey() async {
    await AppSettings.instance.setApiKey('');
    if (mounted) {
      setState(() => _keySet = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.aSettingsKeyRemoved)));
    }
  }

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context)!;
    await _save();
    if (!mounted) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final svc = OpenRouterService();
      final reply = await svc.ask(prompt: 'Reply with the single word: OK');
      final via = svc.lastModelUsed;
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = l10n.aSettingsTestSuccess(reply.trim()) +
            (via != null ? '\n${l10n.aSettingsModelUsed(via)}' : '');
      });
    } on OpenRouterException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = l10n.operationFailed(describeError(e, l10n));
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isCustom = _provider == AppConfig.providerCustom;
    final isManaged = _provider == AppConfig.providerManaged;
    final needsKey = _def.needsKey;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.aSettingsIntro,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Appearance (theme mode)
          _sectionTitle(l10n.appearance, Icons.brightness_6_outlined),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance.mode,
            builder: (context, mode, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: ThemeMode.system, icon: const Icon(Icons.brightness_auto), label: Text(l10n.aSettingsThemeSystem)),
                ButtonSegment(
                    value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(l10n.aSettingsThemeLight)),
                ButtonSegment(
                    value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(l10n.aSettingsThemeDark)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ThemeController.instance.set(s.first),
            ),
          ),
          const SizedBox(height: 20),

          // Language
          _sectionTitle(l10n.language, Icons.language_outlined),
          const SizedBox(height: 8),
          ValueListenableBuilder<Locale?>(
            valueListenable: LocaleController.instance.locale,
            builder: (context, locale, _) => DropdownButtonFormField<String>(
              value: locale?.languageCode ?? '',
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [
                DropdownMenuItem(value: '', child: Text(l10n.systemDefault)),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                const DropdownMenuItem(value: 'es', child: Text('Español')),
                const DropdownMenuItem(value: 'ar', child: Text('العربية')),
                const DropdownMenuItem(value: 'ku', child: Text('کوردی')),
                const DropdownMenuItem(value: 'fa', child: Text('فارسی')),
              ],
              onChanged: (v) => LocaleController.instance
                  .set((v == null || v.isEmpty) ? null : Locale(v)),
            ),
          ),
          const SizedBox(height: 20),

          // Provider
          _sectionTitle(l10n.aSettingsProvider, Icons.hub_outlined),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provider,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: AppConfig.providers
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.id == AppConfig.providerCustom ? l10n.aiProviderCustom : p.label, overflow: TextOverflow.ellipsis, maxLines: 1),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) _onProviderChanged(v);
            },
          ),
          const SizedBox(height: 16),

          // API key (only if provider needs one)
          if (needsKey) ...[
            _sectionTitle(l10n.aSettingsApiKey, Icons.key,
                trailing: _keySet ? _badge(l10n.aSettingsKeySet, const Color(0xFF2E9E7B)) : null),
            const SizedBox(height: 8),
            TextField(
              controller: _keyCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _keySet ? l10n.aSettingsReplaceKey : l10n.aSettingsPasteKey(_def.label.split(' ').first),
                prefixIcon: const Icon(Icons.vpn_key, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_def.keysUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.aSettingsGetKeyAt(_def.keysUrl),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
            if (_keySet)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _removeKey,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.aSettingsRemoveKey),
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Custom endpoint (only for custom provider)
          if (isCustom) ...[
            _sectionTitle(l10n.aSettingsServerUrl, Icons.dns_outlined),
            const SizedBox(height: 8),
            TextField(
              controller: _endpointCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.aSettingsEndpoint,
                hintText: 'http://192.168.1.10:1234/v1/chat/completions',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.aSettingsLocalServerHint,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
          ],

          // Managed server URL (only for the managed provider)
          if (isManaged) ...[
            _sectionTitle(l10n.managedServerUrl, Icons.cloud_outlined),
            const SizedBox(height: 8),
            TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.managedServerUrl,
                hintText: l10n.managedServerHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.managedNote, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
          ],

          // Model (the managed provider chooses the model server-side)
          if (!isManaged) ...[
          _sectionTitle(l10n.aSettingsModel, Icons.smart_toy_outlined),
          const SizedBox(height: 8),
          if (_def.models.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _modelChoice,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [
                ..._def.models.map((m) => DropdownMenuItem(
                      value: m.$1,
                      child: Text(m.$1 == 'auto' ? l10n.aiModelAuto : m.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                    )),
                DropdownMenuItem(value: '__custom__', child: Text(l10n.aSettingsCustomModel)),
              ],
              onChanged: (v) => setState(() => _modelChoice = v ?? _modelChoice),
            ),
          if (_def.models.isEmpty || _modelChoice == '__custom__') ...[
            if (_def.models.isNotEmpty) const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: InputDecoration(
                labelText: l10n.aSettingsModelName,
                hintText: l10n.aSettingsModelHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.aSettingsModelTip,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          ],

          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? l10n.aSettingsTesting : l10n.aSettingsTest),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(l10n.save),
              ),
            ),
          ]),

          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testOk ? const Color(0xFF2E9E7B) : cs.error).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(_testOk ? Icons.check_circle : Icons.error_outline,
                    color: _testOk ? const Color(0xFF2E9E7B) : cs.error, size: 20),
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      );
}
