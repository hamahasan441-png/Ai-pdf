import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

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
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('AI PDF'),
        ]),
        actions: [
          IconButton(
            icon: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_outlined, size: 20),
            ),
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.logout, size: 20),
            ),
            onPressed: () async {
              await ref.read(apiClientProvider).clearTokens();
              if (mounted) context.go('/login');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              // Hero banner
              SliverToBoxAdapter(child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Smart Documents', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Upload, analyze & edit with AI', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
                    const SizedBox(height: 16),
                    SizedBox(height: 40, child: ElevatedButton.icon(
                      onPressed: () => context.push('/upload'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Document', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                  ])),
                  const SizedBox(width: 16),
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.auto_awesome, size: 32, color: Colors.white),
                  ),
                ]),
              )),
              // Quick actions
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _QuickAction(icon: Icons.upload_file, label: 'Upload', color: AppColors.primary, onTap: () => context.push('/upload')),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.draw, label: 'Editor', color: AppColors.accent, onTap: () {}),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.folder_outlined, label: 'Files', color: AppColors.success, onTap: () {}),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.auto_awesome, label: 'AI Fill', color: const Color(0xFF7C3AED), onTap: () {}),
                ]),
              )),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              // Documents header
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('Recent Documents', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_docs.length} files', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ]),
              )),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              // Documents list
              _docs.isEmpty
                  ? SliverFillRemaining(child: _buildEmpty(cs))
                  : SliverList(delegate: SliverChildBuilderDelegate(
                      (_, i) => _DocCard(doc: _docs[i]),
                      childCount: _docs.length,
                    )),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/upload'),
        icon: const Icon(Icons.add),
        label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(28)),
        child: Icon(Icons.description_outlined, size: 48, color: cs.outline),
      ),
      const SizedBox(height: 24),
      Text('No Documents Yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Upload a PDF, Word, or image to start editing', style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
    ]),
  ));
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.15))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ));
  }
}

class _DocCard extends StatelessWidget {
  final dynamic doc;
  const _DocCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final name = doc['original_filename'] ?? 'Document';
    final status = doc['status'] ?? 'uploaded';
    final id = doc['id'] ?? '';
    final cs = Theme.of(context).colorScheme;
    final statusColor = status == 'filled' || status == 'exported' ? AppColors.success : status == 'error' ? AppColors.error : AppColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/document/$id'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(status.toString().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ]),
            ])),
            IconButton(
              icon: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit_note, size: 18, color: AppColors.accent),
              ),
              onPressed: () => context.push('/editor/$id'),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ]),
        ),
      ),
    );
  }
}
