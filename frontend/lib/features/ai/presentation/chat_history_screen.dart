import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import 'package:ai_pdf/core/network/api_client.dart';
import 'package:ai_pdf/core/services/auto_backup_service.dart';

/// Chat History Screen — E2.3 Enhancement-Based Masterplan.
///
/// Lists past AI chat sessions per document hash, with restore, delete, and offline fallback.
/// Backend: GET /api/v1/chat-history (list), GET /{id} (detail), DELETE /{id}.
/// Offline fallback: AutoBackupService local cache when backend unreachable.
class ChatHistoryScreen extends ConsumerStatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_Session> _sessions = [];

  final _backup = const AutoBackupService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/chat-history');
      final List data = resp.data as List;
      final sessions = data.map((j) => _Session.fromJson(j)).toList();
      // Sort newest first (backend already, but ensure)
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } on DioException catch (e) {
      // Offline fallback — try local backup
      try {
        final local = await _backup.listBackups();
        // Map local backups to session-like items? For now show empty + error with offline note
        // In future, map auto_backup JSON to _Session
        setState(() {
          _loading = false;
          _error = e.response?.statusCode == 401
              ? 'Login required to see chat history'
              : 'Backend unreachable — showing offline mode (on-device answers only). ${e.message}';
          _sessions = [];
        });
      } catch (_) {
        setState(() {
          _loading = false;
          _error = 'Failed to load chat history: ${e.message}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This will permanently delete this chat session and all its messages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/chat-history/$id');
      setState(() {
        _sessions.removeWhere((s) => s.id == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _restore(_Session session) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/chat-history/${session.id}');
      final detail = _SessionDetail.fromJson(resp.data);
      if (!mounted) return;
      // Push to AI chat screen with restored history
      // For V1, we pass document_id and history via extra
      context.push('/ai', extra: {
        'documentId': detail.documentId,
        'restoredMessages': detail.messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
        'sessionId': detail.id,
        'title': detail.title,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _sessions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 64, color: cs.outline),
                            const SizedBox(height: 16),
                            const Text('No chat history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            const Text(
                              'Your document chats will appear here. Start a chat with a PDF to see page-cited answers, then come back to resume.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => context.push('/ai'),
                              icon: const Icon(Icons.psychology),
                              label: const Text('Start new chat'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final s = _sessions[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.chat_bubble, color: cs.onPrimaryContainer, size: 20),
                            ),
                            title: Text(s.title.isEmpty ? 'Untitled chat' : s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (s.documentId != null) Text('Doc: ${s.documentId}', style: TextStyle(fontSize: 11, color: cs.outline)),
                                Text(
                                  '${s.messageCount} messages • ${s.updatedAt.toLocal().toString().split('.').first}',
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'restore') _restore(s);
                                if (v == 'delete') _delete(s.id);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'restore', child: Text('Restore')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                            onTap: () => _restore(s),
                          ),
                        );
                      },
                    ),
      floatingActionButton: _sessions.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/ai'),
              icon: const Icon(Icons.add),
              label: const Text('New chat'),
            ),
    );
  }
}

// --- Models ---

class _Session {
  final String id;
  final String title;
  final String? documentId;
  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  _Session({
    required this.id,
    required this.title,
    this.documentId,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        documentId: j['document_id'] as String?,
        messageCount: j['message_count'] as int? ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}

class _SessionDetail {
  final String id;
  final String title;
  final String? documentId;
  final List<_Message> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  _SessionDetail({
    required this.id,
    required this.title,
    this.documentId,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _SessionDetail.fromJson(Map<String, dynamic> j) => _SessionDetail(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        documentId: j['document_id'] as String?,
        messages: (j['messages'] as List).map((m) => _Message.fromJson(m as Map<String, dynamic>)).toList(),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}

class _Message {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  _Message({required this.id, required this.role, required this.content, required this.createdAt});

  factory _Message.fromJson(Map<String, dynamic> j) => _Message(
        id: j['id'] as String,
        role: j['role'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
