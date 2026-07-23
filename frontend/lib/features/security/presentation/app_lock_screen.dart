import 'package:flutter/material.dart';

import 'package:ai_pdf/features/security/data/biometric_service.dart';

/// Full-screen lock gate shown on app resume when biometric lock is enabled.
///
/// Displays a branded splash with a "Unlock" button that triggers biometric
/// authentication. On success, pops itself and reveals the app. On failure,
/// stays locked (user can retry).
class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _bio = BiometricService();
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    // Auto-trigger on first show.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);

    final result = await _bio.authenticate(reason: 'Unlock AI PDF');
    if (result == BiometricResult.success) {
      widget.onUnlocked();
    }

    if (mounted) setState(() => _authenticating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('AI PDF is locked', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Use fingerprint or face to unlock',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _authenticating ? null : _authenticate,
              icon: const Icon(Icons.fingerprint),
              label: Text(_authenticating ? 'Authenticating…' : 'Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
