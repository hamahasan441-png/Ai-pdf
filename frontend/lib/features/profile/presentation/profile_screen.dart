import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/config/app_settings.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final Map<String, TextEditingController> _c = {};
  final _serverCtrl = TextEditingController(text: AppSettings.instance.apiBaseUrl);
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
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) c.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    await AppSettings.instance.setApiBaseUrl(_serverCtrl.text);
    ref.read(apiClientProvider).updateBaseUrl(AppSettings.instance.apiBaseUrl);
    _serverCtrl.text = AppSettings.instance.apiBaseUrl;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Backend server updated')));
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
      for (final f in _fields) {
        _c[f.$1] = TextEditingController();
      }
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile saved!')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Save failed')));
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile'), actions: [
        IconButton(
          icon: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          onPressed: _saving ? null : _save,
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('Your data is stored to help auto-fill forms.',
                  style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Link to the dedicated AI Settings screen.
        Card(
          child: ListTile(
            leading: Icon(Icons.smart_toy_outlined, color: cs.primary),
            title: const Text('AI Settings'),
            subtitle: const Text('Provider, API key, model (OpenRouter, OpenAI, Claude…)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
        ),
        const SizedBox(height: 12),
        // Optional backend server (account-based/legacy flows).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [
                Icon(Icons.cloud_outlined, size: 20),
                SizedBox(width: 8),
                Text('Backend server (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Only for account features. On-device AI and file tools do NOT need this.',
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
        const SizedBox(height: 16),
        ..._fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                controller: _c[f.$1],
                decoration: InputDecoration(labelText: f.$2, prefixIcon: Icon(f.$3, size: 20)),
              ),
            )),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save Profile'),
          ),
        ),
      ]),
    );
  }
}
