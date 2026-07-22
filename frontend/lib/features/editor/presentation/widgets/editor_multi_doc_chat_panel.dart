import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_multi_doc_chat_controller.dart';

/// Sliding panel for AI chat across multiple open documents (Phase 31).
///
/// Shows the document context chips, message history (user/assistant bubbles
/// with citations), a text input, and loading/error states. Positioned as a
/// right-side panel over the editor — the caller animates the slide.
class EditorMultiDocChatPanel extends StatefulWidget {
  final EditorMultiDocChatState chatState;
  final ValueChanged<String> onSend;
  final VoidCallback onNewSession;
  final VoidCallback onClose;
  final ValueChanged<String> onRemoveDocument;
  final void Function(int page, String docName)? onCitationTap;

  const EditorMultiDocChatPanel({
    super.key,
    required this.chatState,
    required this.onSend,
    required this.onNewSession,
    required this.onClose,
    required this.onRemoveDocument,
    this.onCitationTap,
  });

  @override
  State<EditorMultiDocChatPanel> createState() =>
      _EditorMultiDocChatPanelState();
}

class _EditorMultiDocChatPanelState extends State<EditorMultiDocChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    // Auto-scroll to bottom after a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 320,
        child: Column(
          children: [
            _header(cs),
            if (widget.chatState.hasDocuments) _documentChips(cs),
            const Divider(height: 1),
            Expanded(child: _messageList(cs)),
            if (widget.chatState.error != null) _errorBanner(cs),
            _inputRow(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI Chat (${widget.chatState.documentCount} docs)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            onPressed: widget.onNewSession,
            tooltip: 'New session',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onClose,
            tooltip: 'Close',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _documentChips(ColorScheme cs) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final doc in widget.chatState.documents)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                label: Text(doc.name, style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => widget.onRemoveDocument(doc.id),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _messageList(ColorScheme cs) {
    final messages = widget.chatState.messages;
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Ask anything about your documents',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length + (widget.chatState.loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == messages.length) return _loadingBubble(cs);
        return _bubble(messages[i], cs);
      },
    );
  }

  Widget _bubble(ChatMessage msg, ColorScheme cs) {
    final isUser = msg.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 270),
        decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
            if (msg.citations.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  for (final c in msg.citations)
                    GestureDetector(
                      onTap: () => widget.onCitationTap
                          ?.call(c.pageIndex ?? 0, c.documentName),
                      child: Text(
                        '[${c.documentName}${c.pageIndex != null ? ' p.${c.pageIndex! + 1}' : ''}]',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadingBubble(ColorScheme cs) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: 40,
          child: LinearProgressIndicator(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: cs.errorContainer,
      child: Text(
        widget.chatState.error!,
        style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
      ),
    );
  }

  Widget _inputRow(ColorScheme cs) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Ask a question...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send,
                  color: widget.chatState.loading
                      ? cs.onSurface.withOpacity(0.3)
                      : cs.primary),
              onPressed: widget.chatState.loading ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
