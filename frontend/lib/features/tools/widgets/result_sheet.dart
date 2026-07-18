import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/ads/ads_service.dart';
import '../../../core/services/recent_files_service.dart';
import '../services/output_actions.dart';

/// Shows a professional result sheet after a tool finishes.
/// Offers Preview, Save to device, and Share for the output file(s).
///
/// Every output is automatically recorded in Recent Files and mirrored to the
/// browsable "Pdoczy" folder on device storage.
Future<void> showResultSheet(
  BuildContext context, {
  required List<String> paths,
  String title = 'Done!',
  String? subtitle,
}) {
  // Track + persist every produced file (fire-and-forget, non-blocking).
  for (final p in paths) {
    RecentFilesService.instance.add(p, action: title);
    OutputActions.mirrorToPublicFolder(p);
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ResultSheet(paths: paths, title: title, subtitle: subtitle),
  ).whenComplete(() {
    // Finishing a tool is a natural break — maybe show a (capped) interstitial
    // to free users. No-op for Pro.
    AdsService.instance.maybeShowInterstitial();
  });
}

class _ResultSheet extends StatelessWidget {
  final List<String> paths;
  final String title;
  final String? subtitle;
  const _ResultSheet({required this.paths, required this.title, this.subtitle});

  bool get _isPdf => paths.isNotEmpty && paths.first.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 32),
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            Text(
              paths.length == 1 ? paths.first.split('/').last : '${paths.length} files',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (paths.length == 1)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.visibility_outlined,
                      label: 'Preview',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => FilePreviewScreen(path: paths.first, isPdf: _isPdf),
                        ));
                      },
                    ),
                  ),
                if (paths.length == 1) const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.download_outlined,
                    label: 'Save',
                    onTap: () async {
                      if (paths.length == 1) {
                        await OutputActions.save(context, paths.first);
                      } else {
                        for (final p in paths) {
                          if (!context.mounted) break;
                          await OutputActions.save(context, p);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    primary: true,
                    onTap: () => OutputActions.shareMany(context, paths),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: primary ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: primary ? cs.onPrimary : cs.onSurface, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary ? cs.onPrimary : cs.onSurface,
                )),
          ],
        ),
      ),
    );
  }
}

/// Memory-safe in-app preview (pdfx pinch viewer for PDF, Image for images).
class FilePreviewScreen extends StatefulWidget {
  final String path;
  final bool isPdf;
  const FilePreviewScreen({super.key, required this.path, required this.isPdf});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  PdfControllerPinch? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) {
      _controller = PdfControllerPinch(
        document: PdfDocument.openFile(widget.path),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => OutputActions.save(context, widget.path),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => OutputActions.share(context, widget.path),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF2B2B2B),
      body: widget.isPdf
          ? PdfViewPinch(controller: _controller!)
          : InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(widget.path))),
            ),
    );
  }
}
