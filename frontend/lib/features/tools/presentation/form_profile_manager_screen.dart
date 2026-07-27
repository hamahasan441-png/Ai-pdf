import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:ai_pdf/features/editor/data/form_profile_service.dart';

/// Form Profiles Manager — E3.4 Enhancement-Based Masterplan.
///
/// Lists all saved form profiles (per form type), lets the user:
/// - View field values
/// - Edit in JSON
/// - Export/import JSON
/// - Delete
///
/// Persisted via FormProfileService (SharedPreferences, encrypted via OS keystore).
class FormProfileManagerScreen extends StatefulWidget {
  const FormProfileManagerScreen({super.key});

  @override
  State<FormProfileManagerScreen> createState() => _FormProfileManagerScreenState();
}

class _FormProfileManagerScreenState extends State<FormProfileManagerScreen> {
  final FormProfileService _service = const FormProfileService();
  List<FormProfile> _profiles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load all profile keys then their values
      final keys = await _service.listProfiles();
      final List<FormProfile> all = [];
      for (final k in keys) {
        final values = await _service.loadProfile(k);
        all.add(FormProfile(formType: k, fieldValues: values, savedAt: DateTime.now()));
      }
      // Sort newest first by formType
      all.sort((a, b) => a.formType.compareTo(b.formType));
      setState(() {
        _profiles = all;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _delete(FormProfile p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Delete profile for "${p.formType}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteProfile(p.formType);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${p.formType}')));
    }
  }

  Future<void> _export(FormProfile p) async {
    final jsonStr = jsonEncode(p.toJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copied to clipboard'),
              subtitle: Text('${p.fieldValues.length} fields'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share JSON'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.pop(ctx, 'close'),
            ),
          ],
        ),
      ),
    );
    if (action == 'share') {
      final tmp = await _writeTempFile('${p.formType}.json', jsonStr);
      if (tmp != null) {
        await Share.shareXFiles([XFile(tmp)], text: 'Form profile: ${p.formType}');
      }
    }
  }

  Future<String?> _writeTempFile(String name, String content) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(content);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import profile JSON'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '{"formType":"...", "fieldValues":{...}}',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Import')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    try {
      final map = jsonDecode(result) as Map<String, dynamic>;
      final profile = FormProfile.fromJson(map);
      if (profile.formType.isEmpty || profile.fieldValues.isEmpty) {
        throw const FormatException('Invalid profile: empty formType or fieldValues');
      }
      await _service.saveProfile(formType: profile.formType, fieldValues: profile.fieldValues);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${profile.formType}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Profiles'),
        actions: [
          IconButton(icon: const Icon(Icons.download), tooltip: 'Import JSON', onPressed: _import),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _profiles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_off, size: 64, color: cs.outline),
                            const SizedBox(height: 16),
                            const Text('No saved form profiles', style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 8),
                            const Text(
                              'When you fill a form and place values, they are saved as a reusable profile for that form type. '
                              'Next time the same form appears, values are auto-suggested.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _profiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final p = _profiles[i];
                        return Card(
                          child: ExpansionTile(
                            title: Text(p.formType, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${p.fieldValues.length} fields • Saved ${p.savedAt.toLocal()}'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final entry in p.fieldValues.entries)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: Text(entry.key,
                                                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500)),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              flex: 3,
                                              child: Text(entry.value),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _export(p),
                                          icon: const Icon(Icons.ios_share),
                                          label: const Text('Export'),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          onPressed: () => _delete(p),
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: _profiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import'),
            ),
    );
  }
}
