import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// ToolsScreen - Hub for all document tools.
///
/// Clearly separates:
///   OFFLINE tools (work without internet, on-device)
///   ONLINE tools (require AI backend)
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tools)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // OFFLINE section
          _SectionHeader(
            icon: Icons.offline_bolt,
            title: l10n.toolsOfflineTitle,
            subtitle: l10n.toolsOfflineSubtitle,
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _ToolCard(
                icon: Icons.image,
                label: l10n.toolJpgToPdf,
                desc: l10n.toolJpgToPdfDesc,
                color: const Color(0xFF2E5BBA),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/jpg-to-pdf'),
              ),
              _ToolCard(
                icon: Icons.compress,
                label: l10n.toolCompress,
                desc: l10n.toolCompressDesc,
                color: const Color(0xFF10B981),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/compress'),
              ),
              _ToolCard(
                icon: Icons.merge_type,
                label: l10n.toolMerge,
                desc: l10n.toolMergeDesc,
                color: const Color(0xFF7C3AED),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/merge'),
              ),
              _ToolCard(
                icon: Icons.call_split,
                label: l10n.toolSplit,
                desc: l10n.toolSplitDesc,
                color: const Color(0xFFF59E0B),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/split'),
              ),
              _ToolCard(
                icon: Icons.draw,
                label: l10n.toolEditor,
                desc: l10n.toolEditorDesc,
                color: const Color(0xFFEF4444),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/pick-edit'),
              ),
              _ToolCard(
                icon: Icons.dashboard_customize,
                label: l10n.toolOrganize,
                desc: l10n.toolOrganizeDesc,
                color: const Color(0xFF0EA5E9),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/organize'),
              ),
              _ToolCard(
                icon: Icons.document_scanner,
                label: l10n.toolExtractText,
                desc: l10n.toolExtractTextDesc,
                color: const Color(0xFF14B8A6),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/ocr'),
              ),
              _ToolCard(
                icon: Icons.collections,
                label: l10n.toolPdfToImages,
                desc: l10n.toolPdfToImagesDesc,
                color: const Color(0xFF8B5CF6),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/pdf-to-images'),
              ),
              _ToolCard(
                icon: Icons.branding_watermark,
                label: l10n.toolWatermark,
                desc: l10n.toolWatermarkDesc,
                color: const Color(0xFF6366F1),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/watermark'),
              ),
              _ToolCard(
                icon: Icons.numbers,
                label: l10n.toolPageNumbers,
                desc: l10n.toolPageNumbersDesc,
                color: const Color(0xFF0891B2),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/page-numbers'),
              ),
              _ToolCard(
                icon: Icons.rotate_right,
                label: l10n.toolRotate,
                desc: l10n.toolRotateDesc,
                color: const Color(0xFFD97706),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/rotate'),
              ),
              _ToolCard(
                icon: Icons.content_cut,
                label: l10n.toolExtractPages,
                desc: l10n.toolExtractPagesDesc,
                color: const Color(0xFFE11D48),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/extract-pages'),
              ),
              _ToolCard(
                icon: Icons.delete_sweep,
                label: l10n.toolDeletePages,
                desc: l10n.toolDeletePagesDesc,
                color: const Color(0xFFBE123C),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/delete-pages'),
              ),
              _ToolCard(
                icon: Icons.text_snippet,
                label: l10n.toolPdfToText,
                desc: l10n.toolPdfToTextDesc,
                color: const Color(0xFF059669),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/pdf-to-text'),
              ),
              _ToolCard(
                icon: Icons.approval,
                label: l10n.toolStampImage,
                desc: l10n.toolStampImageDesc,
                color: const Color(0xFF9333EA),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/stamp-image'),
              ),
              _ToolCard(
                icon: Icons.headphones,
                label: l10n.readAloud,
                desc: l10n.readAloudDesc,
                color: const Color(0xFF0D9488),
                badge: l10n.badgeOffline,
                onTap: () => context.push('/tools/read-aloud'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ONLINE section
          _SectionHeader(
            icon: Icons.auto_awesome,
            title: l10n.toolsAiTitle,
            subtitle: l10n.toolsAiSubtitle,
            color: cs.primary,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _ToolCard(
                icon: Icons.psychology,
                label: l10n.toolUnderstand,
                desc: l10n.toolUnderstandDesc,
                color: const Color(0xFF7C3AED),
                badge: 'AI',
                badgeColor: cs.primary,
                onTap: () => context.push('/ai'),
              ),
              _ToolCard(
                icon: Icons.edit_note,
                label: l10n.toolAutoFill,
                desc: l10n.toolAutoFillDesc,
                color: const Color(0xFFDB2777),
                badge: 'AI',
                badgeColor: cs.primary,
                onTap: () => context.push('/ai-form'),
              ),
              _ToolCard(
                icon: Icons.sync_alt,
                label: l10n.convert,
                desc: l10n.convertDesc,
                color: const Color(0xFF2B579A),
                badge: l10n.badgeCloud,
                badgeColor: cs.primary,
                onTap: () => context.push('/tools/convert'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ]);
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final String badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.badge,
    required this.onTap,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bColor = badgeColor ?? AppColors.success;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: bColor),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
