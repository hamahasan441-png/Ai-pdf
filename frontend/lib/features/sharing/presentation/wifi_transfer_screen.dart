import 'dart:io';

import 'package:flutter/material.dart';

/// Wi-Fi Direct file transfer screen — share PDFs between devices on the
/// same network without internet.
///
/// Creates a temporary HTTP server on a random port, displays a QR code
/// with the download URL, and serves the file until the user dismisses
/// the screen. The receiving device scans the QR code or enters the URL
/// in a browser to download the file.
///
/// This is the privacy-first alternative to cloud sharing — no upload,
/// no account, no internet required. Works on any local network.
class WifiTransferScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const WifiTransferScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<WifiTransferScreen> createState() => _WifiTransferScreenState();
}

class _WifiTransferScreenState extends State<WifiTransferScreen> {
  HttpServer? _server;
  String? _url;
  int _downloads = 0;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      // Get the device's local IP address.
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ip = interfaces
          .expand((i) => i.addresses)
          .firstWhere(
            (a) => !a.isLoopback,
            orElse: () => InternetAddress.loopbackIPv4,
          )
          .address;

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = _server!.port;

      setState(() {
        _url = 'http://$ip:$port/${Uri.encodeComponent(widget.fileName)}';
        _starting = false;
      });

      await for (final request in _server!) {
        if (request.method == 'GET') {
          final file = File(widget.filePath);
          if (await file.exists()) {
            request.response
              ..headers.contentType = ContentType('application', 'pdf')
              ..headers.add('Content-Disposition', 'attachment; filename="${widget.fileName}"')
              ..add(await file.readAsBytes());
            await request.response.close();
            if (mounted) setState(() => _downloads++);
          } else {
            request.response
              ..statusCode = 404
              ..write('File not found');
            await request.response.close();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _url = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start server: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Transfer')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              if (_starting)
                const CircularProgressIndicator()
              else if (_url != null) ...[
                Text(
                  'Open this URL on the other device:',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _url!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'Downloads: $_downloads',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Both devices must be on the same Wi-Fi network.\n'
                  'No internet or account needed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else
                Text(
                  'Could not start transfer server.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
