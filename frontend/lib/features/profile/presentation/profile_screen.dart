import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/form_memory_service.dart';
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
    for (final c in _c.values) {
      c.dispose();
    }
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await UserProfileService.instance.load();
    await FormMemoryService.instance.load();
    final data = UserProfileService.instance.data;
    for (final f in UserProfileService.fields) {
      _c[f.$1] = TextEditingController(text: data[f.$1] ?? '');
    }
    setState(() => _loading = false);
  }

  Future<void> _clearMemory() async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.bProfileForgetTitle),
        content: Text(l.bProfileForgetBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.bProfileForget)),
        ],
      ),
    );
    if (ok == true) {
      await FormMemoryService.instance.clear();
      if (mounted) setState(() {});
    }
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
          SnackBar(content: Text(AppLocalizations.of(context)!.bProfileSaved)));
    }
  }

  Future<void> _clear() async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.bProfileClearTitle),
        content: Text(l.bProfileClearBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.clear)),
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
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.bProfileServerUpdated)));
    }
  }

  String _fieldLabel(AppLocalizations l, (String, String) f) => switch (f.$1) {
        'first_name' => l.bProfileFieldFirstName,
        'last_name' => l.bProfileFieldLastName,
        'date_of_birth' => l.bProfileFieldDateOfBirth,
        'nationality' => l.bProfileFieldNationality,
        'phone_number' => l.bProfileFieldPhone,
        'email' => l.bProfileFieldEmail,
        'street_address' => l.bProfileFieldAddress,
        'city' => l.bProfileFieldCity,
        'postal_code' => l.bProfileFieldPostalCode,
        'country' => l.bProfileFieldCountry,
        'id_number' => l.bProfileFieldIdNumber,
        'employer_name' => l.bProfileFieldEmployer,
        'job_title' => l.bProfileFieldJobTitle,
        _ => f.$2,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l.bProfileTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.myProfile), actions: [
        IconButton(
          tooltip: l.clear,
          icon: const Icon(Icons.delete_outline),
          onPressed: _clear,
        ),
        IconButton(
          tooltip: l.save,
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
            color: cs.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.lock_outline, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.bProfileEncryptedNote,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.smart_toy_outlined, color: cs.primary),
            title: Text(l.aiSettings),
            subtitle: Text(l.bProfileAiSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
        ),
        ValueListenableBuilder<Map<String, String>>(
          valueListenable: FormMemoryService.instance.notifier,
          builder: (context, mem, _) {
            final count = mem.length;
            return Card(
              child: ListTile(
                leading: Icon(Icons.history_edu_outlined, color: cs.primary),
                title: Text(l.bProfileRememberedTitle),
                subtitle: Text(count == 0
                    ? l.bProfileRememberedEmpty
                    : l.bProfileRememberedCount(count)),
                trailing: count == 0
                    ? null
                    : TextButton(onPressed: _clearMemory, child: Text(l.bProfileForget)),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ...UserProfileService.fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: _c[f.$1],
                decoration: InputDecoration(
                  labelText: _fieldLabel(l, f),
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
            label: Text(l.bProfileSaveProfile),
          ),
        ),
        const SizedBox(height: 20),
        // Optional backend (account/legacy flows).
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: Text(l.bProfileBackendTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(l.bProfileBackendSubtitle, style: const TextStyle(fontSize: 12)),
          children: [
            TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.bProfileBackendUrl,
                hintText: l.managedServerHint,
                prefixIcon: const Icon(Icons.link, size: 20),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _saveServer,
                icon: const Icon(Icons.save, size: 18),
                label: Text(l.bProfileSaveServer),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
