import 'package:flutter/material.dart';

/// Bottom sheet with sharing options: Share PDF, Share as images, Share text,
/// Copy link, QR code.
///
/// Shown from the editor/viewer when the user taps the share button.
class ShareOptionsSheet extends StatelessWidget {
  final VoidCallback onSharePdf;
  final VoidCallback onShareImages;
  final VoidCallback onShareText;
  final VoidCallback? onCopyLink;

  const ShareOptionsSheet({
    super.key,
    required this.onSharePdf,
    required this.onShareImages,
    required this.onShareText,
    this.onCopyLink,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('Share', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Share as PDF'),
            subtitle: const Text('Original quality, all annotations included'),
            onTap: () {
              Navigator.pop(context);
              onSharePdf();
            },
          ),
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Share as images'),
            subtitle: const Text('Each page as a JPG image'),
            onTap: () {
              Navigator.pop(context);
              onShareImages();
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_snippet),
            title: const Text('Share extracted text'),
            subtitle: const Text('Plain text from OCR'),
            onTap: () {
              Navigator.pop(context);
              onShareText();
            },
          ),
          if (onCopyLink != null)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy share link'),
              subtitle: const Text('Anyone with the link can view'),
              onTap: () {
                Navigator.pop(context);
                onCopyLink!();
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
