import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/services/recent_files_service.dart';
import '../../../core/services/permission_service.dart';
import '../../tools/widgets/result_sheet.dart';

/// On-device home. No account / backend: everything here works offline and the
/// only "recent" concept is files created/edited/saved on this device.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    RecentFilesService.instance.load();
    // Ask for storage / gallery / camera access on first launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PermissionService.ensureOnStartup(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Pdoczy'),
        ]),
        actions: [
          IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.workspace_premium, size: 20, color: Colors.white),
            ),
            tooltip: l10n.upgradeToPro,
            onPressed: () => context.push('/paywall'),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.key, size: 20),
            ),
            tooltip: 'AI settings & API key',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.history, size: 20),
            ),
            tooltip: 'Recent files',
            onPressed: () => context.push('/recent'),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person_outlined, size: 20),
            ),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(slivers: [
        // Hero banner
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l10n.smartDocuments, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(l10n.appTagline, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/tools'),
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: Text(l10n.openTools, style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.auto_awesome, size: 32, color: Colors.white),
              ),
            ]),
          ),
        ),
        // Quick actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _QuickAction(icon: Icons.grid_view_rounded, label: l10n.tools, color: AppColors.primary, onTap: () => context.push('/tools')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.folder_special, label: 'Library', color: const Color(0xFF5C6BC0), onTap: () => context.push('/library')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.document_scanner, label: 'Scan', color: const Color(0xFF2E9E7B), onTap: () => context.push('/tools/scan')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.psychology, label: l10n.askAi, color: const Color(0xFF7E7BD4), onTap: () => context.push('/ai')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.edit_note, label: l10n.fillForm, color: const Color(0xFF6366D8), onTap: () => context.push('/ai-form')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.auto_fix_high, label: l10n.smartFormFiller, color: const Color(0xFFE67E22), onTap: () => context.push('/tools/smart-fill')),
              const SizedBox(width: 12),
              _QuickAction(icon: Icons.draw, label: l10n.editor, color: AppColors.accent, onTap: () => context.push('/tools/pick-edit')),
            ]),
          ),
        ),
        // Recent files (created / edited / saved on this device)
        _recentFilesSliver(cs),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        // Empty-state hint when there are no recent files yet.
        SliverToBoxAdapter(child: _RecentEmptyHint(cs: cs)),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/tools/pick-edit'),
        icon: const Icon(Icons.file_open_outlined),
        label: Text(l10n.openPdf, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _recentFilesSliver(ColorScheme cs) {
    return SliverToBoxAdapter(
      child: ValueListenableBuilder<List<RecentFile>>(
        valueListenable: RecentFilesService.instance.notifier,
        builder: (context, items, _) {
          if (items.isEmpty) return const SizedBox.shrink();
          final l10n = AppLocalizations.of(context)!;
          final show = items.take(6).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text(l10n.recentFiles, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push('/recent'),
                    child: Text(l10n.seeAll),
                  ),
                ]),
              ),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: show.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final f = show[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => FilePreviewScreen(path: f.path, isPdf: f.isPdf),
                      )),
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: (f.isPdf ? AppColors.error : AppColors.primary).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(f.isPdf ? Icons.picture_as_pdf : Icons.image, color: f.isPdf ? AppColors.error : AppColors.primary, size: 22),
                            ),
                            const Spacer(),
                            Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shown only when there are no recent files: a friendly "get started" panel.
class _RecentEmptyHint extends StatelessWidget {
  final ColorScheme cs;
  const _RecentEmptyHint({required this.cs});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecentFile>>(
      valueListenable: RecentFilesService.instance.notifier,
      builder: (context, items, _) {
        if (items.isNotEmpty) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(28)),
                child: Icon(Icons.description_outlined, size: 48, color: cs.outline),
              ),
              const SizedBox(height: 24),
              Text(l10n.getStarted, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                l10n.getStartedBody,
                style: TextStyle(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/tools'),
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label: Text(l10n.openTools),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/ai'),
                    icon: const Icon(Icons.psychology, size: 18),
                    label: Text(l10n.askAi),
                  ),
                ],
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }
}
