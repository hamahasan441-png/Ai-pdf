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
        toolbarHeight: 64,
        title: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Text('Pdoczy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ]),
        actions: [
          _AppBarAction(
            icon: Icons.workspace_premium,
            gradient: AppColors.primaryGradient,
            tooltip: l10n.upgradeToPro,
            onPressed: () => context.push('/paywall'),
          ),
          const SizedBox(width: 6),
          _AppBarAction(
            icon: Icons.key,
            color: cs.surfaceContainerHighest,
            tooltip: 'AI settings & API key',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 6),
          _AppBarAction(
            icon: Icons.history,
            color: cs.surfaceContainerHighest,
            tooltip: 'Recent files',
            onPressed: () => context.push('/recent'),
          ),
          const SizedBox(width: 6),
          _AppBarAction(
            icon: Icons.person_outlined,
            color: cs.surfaceContainerHighest,
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: CustomScrollView(slivers: [
        // Hero banner
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l10n.smartDocuments, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                  const SizedBox(height: 6),
                  Text(l10n.appTagline, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, height: 1.4)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/tools'),
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: Text(l10n.openTools, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
              ),
            ]),
          ),
        ),
        // Quick actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 4),
            child: Text(l10n.quickActions, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _QuickAction(icon: Icons.grid_view_rounded, label: l10n.tools, color: AppColors.primary, onTap: () => context.push('/tools')),
                _QuickAction(icon: Icons.folder_special, label: 'Library', color: const Color(0xFF5C6BC0), onTap: () => context.push('/library')),
                _QuickAction(icon: Icons.document_scanner, label: 'Scan', color: const Color(0xFF2E9E7B), onTap: () => context.push('/tools/scan')),
                _QuickAction(icon: Icons.psychology, label: l10n.askAi, color: const Color(0xFF7E7BD4), onTap: () => context.push('/ai')),
                _QuickAction(icon: Icons.edit_note, label: l10n.fillForm, color: const Color(0xFF6366D8), onTap: () => context.push('/ai-form')),
                _QuickAction(icon: Icons.auto_fix_high, label: l10n.smartFormFiller, color: const Color(0xFFE67E22), onTap: () => context.push('/tools/smart-fill')),
                _QuickAction(icon: Icons.draw, label: l10n.editor, color: AppColors.accent, onTap: () => context.push('/tools/pick-edit')),
              ],
            ),
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

/// Circular/rounded app bar action button with optional gradient or solid color.
class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final Gradient? gradient;
  final Color? color;
  final String tooltip;
  final VoidCallback onPressed;

  const _AppBarAction({
    required this.icon,
    this.gradient,
    this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null ? color : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: gradient != null ? Colors.white : null),
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
