import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Rate & Feedback screen — encourages reviews and collects user feedback.
///
/// Two modes:
/// 1. Rate: directs to Google Play store listing (deep link)
/// 2. Feedback: in-app text form sent to the dev (or stored locally)
class RateFeedbackScreen extends StatefulWidget {
  const RateFeedbackScreen({super.key});

  @override
  State<RateFeedbackScreen> createState() => _RateFeedbackScreenState();
}

class _RateFeedbackScreenState extends State<RateFeedbackScreen> {
  int _rating = 0;
  final _feedbackController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rate & Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Star rating
          Center(
            child: Text('How do you like AI PDF?', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return IconButton(
                iconSize: 40,
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () => setState(() => _rating = i + 1),
              );
            }),
          ),
          const SizedBox(height: 8),
          if (_rating > 0)
            Center(
              child: Text(
                _rating >= 4 ? 'Glad you love it!' : _rating >= 3 ? 'Thank you!' : 'Sorry to hear that',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 24),

          // If rating is high → direct to Play Store
          if (_rating >= 4) ...[
            FilledButton.icon(
              onPressed: _openPlayStore,
              icon: const Icon(Icons.star),
              label: const Text('Rate on Google Play'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _rating = 0),
              icon: const Icon(Icons.feedback),
              label: const Text('Send feedback instead'),
            ),
          ],

          // If rating is low or user chose feedback
          if (_rating > 0 && _rating < 4) ...[
            Text('Tell us how we can improve:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _feedbackController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'What would you like us to fix or add?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _feedbackController.text.isNotEmpty && !_sending ? _sendFeedback : null,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send feedback'),
            ),
          ],

          if (_rating == 0) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Tap a star above to rate your experience',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openPlayStore() {
    // Launch Play Store via platform channel or url_launcher.
    const playUrl = 'market://details?id=com.aidocassistant.app';
    // In production: launchUrl(Uri.parse(playUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening Google Play…')),
    );
  }

  Future<void> _sendFeedback() async {
    setState(() => _sending = true);
    // In production: store locally or send to backend.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your feedback!')),
      );
      Navigator.pop(context);
    }
  }
}
