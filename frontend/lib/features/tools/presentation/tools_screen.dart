import 'package:flutter/material.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // OFFLINE section
          _SectionHeader(
            icon: Icons.offline_bolt,
            title: 'Offline Tools',
            subtitle: 'Work instantly, no internet needed',
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
                label: 'JPG to PDF',
                desc: 'Images → PDF',
                color: const Color(0xFF2E5BBA),
                badge: 'Offline',
                onTap: () => context.push('/tools/jpg-to-pdf'),
              ),
              _ToolCard(
                icon: Icons.compress,
                label: 'Compress',
                desc: 'Shrink files',
                color: const Color(0xFF10B981),
                badge: 'Offline',
                onTap: () => context.push('/tools/compress'),
              ),
              _ToolCard(
                icon: Icons.merge_type,
                label: 'Merge PDF',
                desc: 'Combine files',
                color: const Color(0xFF7C3AED),
                badge: 'Offline',
                onTap: () => context.push('/tools/merge'),
              ),
              _ToolCard(
                icon: Icons.call_split,
                label: 'Split PDF',
                desc: 'Separate pages',
                color: const Color(0xFFF59E0B),
                badge: 'Offline',
                onTap: () => context.push('/tools/split'),
              ),
              _ToolCard(
                icon: Icons.draw,
                label: 'PDF Editor',
                desc: 'Draw, sign, stamp',
                color: const Color(0xFFEF4444),
                badge: 'Offline',
                onTap: () => context.push('/tools/pick-edit'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ONLINE section
          _SectionHeader(
            icon: Icons.auto_awesome,
            title: 'AI Tools',
            subtitle: 'Powered by AI (requires internet)',
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
                label: 'Understand',
                desc: 'AI reads any doc',
                color: const Color(0xFF7C3AED),
                badge: 'AI',
                badgeColor: cs.primary,
                onTap: () => context.push('/upload'),
              ),
              _ToolCard(
                icon: Icons.edit_note,
                label: 'Auto-Fill Form',
                desc: 'AI fills forms',
                color: const Color(0xFFDB2777),
                badge: 'AI',
                badgeColor: cs.primary,
                onTap: () => context.push('/upload'),
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
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
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
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
