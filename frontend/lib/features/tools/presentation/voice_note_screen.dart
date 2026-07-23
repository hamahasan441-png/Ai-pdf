import 'dart:async';

import 'package:flutter/material.dart';

/// Voice note recording screen — record audio annotations tied to a PDF page.
///
/// Users can record a voice memo while viewing a document, and it gets
/// attached to the current page. Useful for accessibility, quick feedback,
/// and collaborative review without typing.
///
/// Uses the platform's microphone via method channel (no heavy native plugin).
class VoiceNoteScreen extends StatefulWidget {
  final int pageNumber;
  final String documentName;

  const VoiceNoteScreen({
    super.key,
    required this.pageNumber,
    required this.documentName,
  });

  @override
  State<VoiceNoteScreen> createState() => _VoiceNoteScreenState();
}

class _VoiceNoteScreenState extends State<VoiceNoteScreen> {
  bool _recording = false;
  bool _recorded = false;
  Duration _duration = Duration.zero;
  Timer? _timer;
  String? _filePath;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _recorded = false;
      _duration = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _duration += const Duration(seconds: 1));
    });
    // In production: start platform audio recorder via method channel.
  }

  void _stopRecording() {
    _timer?.cancel();
    setState(() {
      _recording = false;
      _recorded = true;
      _filePath = 'voice_note_page${widget.pageNumber}.m4a';
    });
    // In production: stop recorder, get file path.
  }

  void _deleteRecording() {
    setState(() {
      _recorded = false;
      _duration = Duration.zero;
      _filePath = null;
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Note — Page ${widget.pageNumber}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Waveform / icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _recording ? 120 : 80,
                height: _recording ? 120 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording
                      ? theme.colorScheme.error.withOpacity(0.15)
                      : theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  _recording ? Icons.mic : Icons.mic_none,
                  size: _recording ? 56 : 40,
                  color: _recording ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // Timer
              Text(
                _formatDuration(_duration),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _recording
                    ? 'Recording…'
                    : _recorded
                        ? 'Recorded'
                        : 'Tap to start',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Controls
              if (!_recorded)
                FilledButton.icon(
                  onPressed: _recording ? _stopRecording : _startRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(_recording ? 'Stop' : 'Record'),
                  style: _recording
                      ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
                      : null,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _deleteRecording,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _filePath),
                      icon: const Icon(Icons.check),
                      label: const Text('Attach to page'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
