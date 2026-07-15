import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/config/app_config.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final Map<String, TextEditingController> _c = {};
  final _serverCtrl = TextEditingController(text: AppSettings.instance.apiBaseUrl);
  final _aiKeyCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController(text: AppSettings.instance.aiModel);
  late String _modelChoice = AppConfig.aiModels.any((m) => m.$1 == AppSettings.instance.aiModel)
      ? AppSettings.instance.aiModel
      : '__custom__';
  bool _keySet = false;
  bool _saving = false;
  bool _loading = true;

  static const _fields = [
    ('first_name', 'First Name', Icons.person),
    ('last_name', 'Last Name', Icons.person_outline),
    ('date_of_birth', 'Date of Birth', Icons.cake),
    ('nationality', 'Nationality', Icons.flag),
    ('phone_number', 'Phone', Icons.phone),
    ('email', 'Email', Icons.email),
    ('street_address', 'Address', Icons.home),
    ('city', 'City', Icons.location_city),
    ('country', 'Country', Icons.public),
    ('passport_number', 'Passport No.', Icons.card_travel),
    ('employer_name', 'Employer', Icons.business),
    ('job_title', 'Job Title', Icons.work),
  ];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in _c.values) c.dispose();
    _serverCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    await AppSettings.instance.setApiBaseUrl(_serverCtrl.text);
    ref.read(apiClientProvider).updateBaseUrl(AppSettings.instance.apiBaseUrl);
    _serverCtrl.text = AppSettings.instance.apiBaseUrl;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI server updated')));
    }
  }

  Future<void> _saveAiKey() async {
    if (_aiKeyCtrl.text.trim().isNotEmpty) {
      await AppSettings.instance.setOpenRouterKey(_aiKeyCtrl.text);
      _aiKeyCtrl.clear();
    }
    final model = _modelChoice == '__custom__' ? _aiModelCtrl.text : _modelChoice;
    await AppSettings.instance.setAiModel(model);
    final set = await AppSettings.instance.hasOpenRouterKey();
    if (mounted) {
      setState(() => _keySet = set);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI key saved on this device')));
    }
  }

  Future<void> _clearAiKey() async {
    await AppSettings.instance.setOpenRouterKey('');
    if (mounted) {
      setState(() => _keySet = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI key removed')));
    }
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.dio.get(AppConstants.profileEndpoint);
      final data = r.data as Map<String, dynamic>? ?? {};
      for (final f in _fields) {
        _c[f.$1] = TextEditingController(text: data[f.$1]?.toString() ?? '');
      }
    } catch (_) {
      for (final f in _fields) { _c[f.$1] = TextEditingController(); }
    }
    _keySet = await AppSettings.instance.hasOpenRouterKey();
    setState(() => _loading = false);
  }


  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = <String, String>{};
      for (final e in _c.entries) {
        if (e.value.text.isNotEmpty) data[e.key] = e.value.text;
      }
      final api = ref.read(apiClientProvider);
      await api.dio.put(AppConstants.profileEndpoint, data: data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved!')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save failed')));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Profile')),
      body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile'), actions: [
        IconButton(
          icon: _saving ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
          onPressed: _saving ? null : _save),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Your data is encrypted and used to auto-fill forms.',
              style: TextStyle(fontSize: 13))),
          ]),
        ),
        const SizedBox(height: 16),
        // AI server configuration (only needed for online AI features).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [
                Icon(Icons.cloud_outlined, size: 20),
                SizedBox(width: 8),
                Text('AI Server (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              const Text(
                'File tools work offline with no server. To enable AI features '
                '(understand documents, auto-fill forms), paste your backend URL.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _serverCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'https://your-server.com/api/v1',
                  prefixIcon: Icon(Icons.link, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _saveServer,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save server'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // OpenRouter key for direct on-device AI (no backend needed).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.key, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI Key (OpenRouter)', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (_keySet)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Set', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Enables AI directly on your phone — no server. Get a free key at '
                'openrouter.ai/keys and paste it here. It is stored encrypted on '
                'this device only (never uploaded or shared).',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _aiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _keySet ? 'Replace key (leave blank to keep)' : 'Paste OpenRouter key (sk-or-...)',
                  prefixIcon: const Icon(Icons.vpn_key, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _modelChoice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'AI model',
                  prefixIcon: Icon(Icons.smart_toy_outlined, size: 20),
                  isDense: true,
                ),
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
                const SizedBox(height: 10),
                TextField(
                  controller: _aiModelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom model slug',
                    hintText: 'provider/model:free',
                    prefixIcon: Icon(Icons.tune, size: 20),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Tip: vision models can read images/PDFs. Free models share a daily '
                'limit — if one is busy, switch to another.',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_keySet)
                    TextButton.icon(
                      onPressed: _clearAiKey,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _saveAiKey,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save AI key'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._fields.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            controller: _c[f.$1],
            decoration: InputDecoration(labelText: f.$2, prefixIcon: Icon(f.$3, size: 20)),
          ),
        )),
        const SizedBox(height: 20),
        SizedBox(height: 50, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('Save Profile'),
        )),
      ]),
    );
  }
}
