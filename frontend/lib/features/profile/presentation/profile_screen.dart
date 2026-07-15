import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/user_profile_service.dart';

/// Your details, stored ENCRYPTED on this device (works offline / in guest
/// mode). Used to auto-fill forms. An optional backend URL is kept for
/// account-based flows.
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

  static const _icons = <String, IconData>{
    'first_name': Icons.person,
    'last_name': Icons.person_outline,
    'date_of_birth': Icons.cake,
    'nationality': Icons.flag,
    'phone_number': Icons.phone,
    'email': Icons.email,
    'street_address': Icons.home,
    'city': Icons.location_city,
    'postal_code': Icons.markunread_mailbox,
    'country': Icons.public,
    'id_number': Icons.badge,
    'employer_name': Icons.business,
    'job_title': Icons.work,
  };

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

  Future<void> _load() async {
    await UserProfileService.instance.load();
    final data = UserProfileService.instance.data;
    for (final f in UserProfileService.fields) {
      _c[f.$1] = TextEditingController(text: data[f.$1] ?? '');
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final values = <String, String>{};
    for (final e in _c.entries) {
      values[e.key] = e.value.text;
    }
    await UserProfileService.instance.save(values);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved on this device')));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear profile?'),
        content: const Text('This removes your saved details from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await UserProfileService.instance.clear();
      for (final c in _c.values) {
        c.clear();
      }
      if (mounted) setState(() {});
    }
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
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_outline),
          onPressed: _clear,
        ),
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
            Icon(Icons.lock_outline, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Saved encrypted on this device only. Used to auto-fill forms — the '
                'AI pre-answers fields it already knows.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.smart_toy_outlined, color: cs.primary),
            title: const Text('AI Settings'),
            subtitle: const Text('Provider, API key, model'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
        ),
        const SizedBox(height: 16),
        ...UserProfileService.fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: _c[f.$1],
                decoration: InputDecoration(
                  labelText: f.$2,
                  prefixIcon: Icon(_icons[f.$1] ?? Icons.edit, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            )),
        const SizedBox(height: 4),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save Profile'),
          ),
        ),
        const SizedBox(height: 20),
        // Optional backend (account/legacy flows).
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: const Text('Backend server (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Not needed for on-device AI or file tools', style: TextStyle(fontSize: 12)),
          children: [
            TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'https://your-server.com/api/v1',
                prefixIcon: Icon(Icons.link, size: 20),
                border: OutlineInputBorder(),
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
      ]),
    );
  }
}
