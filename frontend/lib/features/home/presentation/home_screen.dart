import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<dynamic> _docs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.dio.get(AppConstants.documentsEndpoint);
      setState(() { _docs = (r.data['documents'] as List?) ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI PDF'),
        actions: [
          IconButton(icon: const Icon(Icons.person_outlined), tooltip: 'Profile', onPressed: () => context.push('/profile')),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: () async {
            await ref.read(apiClientProvider).clearTokens();
            if (mounted) context.go('/login');
          }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? _buildEmpty(cs)
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: _docs.length,
                  itemBuilder: (_, i) => _DocCard(doc: _docs[i]),
                )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/upload'),
        icon: const Icon(Icons.add),
        label: const Text('Upload'),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.description_outlined, size: 80, color: cs.outline),
      const SizedBox(height: 20),
      Text('No Documents', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text('Upload a PDF or image to get started', style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: () => context.push('/upload'), icon: const Icon(Icons.upload_file), label: const Text('Upload Document')),
    ]),
  ));
}

class _DocCard extends StatelessWidget {
  final dynamic doc;
  const _DocCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final name = doc['original_filename'] ?? 'Document';
    final status = doc['status'] ?? 'uploaded';
    final id = doc['id'] ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(status.toString().toUpperCase(), style: TextStyle(fontSize: 12, color: status == 'error' ? Colors.red : Colors.green)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit_note, size: 22), tooltip: 'Edit', onPressed: () => context.push('/editor/$id')),
          const Icon(Icons.chevron_right),
        ]),
        onTap: () => context.push('/document/$id'),
      ),
    );
  }
}
