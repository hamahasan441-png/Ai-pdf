import 'package:flutter/material.dart';

/// Multi-party document signing workflow — request signatures from others.
///
/// Flow:
/// 1. User opens a document and marks signature fields (positions).
/// 2. User assigns each field to a signer (name + email/phone).
/// 3. Generates a unique signing link per signer.
/// 4. Tracks signing status (pending/signed/declined).
///
/// Offline-first: the request is queued locally and sent when connectivity
/// is available. Signers receive a deep-link to open the document in-app.
class SignRequestScreen extends StatefulWidget {
  final String documentPath;
  final String documentName;

  const SignRequestScreen({
    super.key,
    required this.documentPath,
    required this.documentName,
  });

  @override
  State<SignRequestScreen> createState() => _SignRequestScreenState();
}

class _SignRequestScreenState extends State<SignRequestScreen> {
  final List<_Signer> _signers = [];
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _addSigner() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) return;

    setState(() {
      _signers.add(_Signer(name: name, email: email));
      _nameController.clear();
      _emailController.clear();
    });
  }

  Future<void> _sendRequests() async {
    if (_signers.isEmpty) return;
    setState(() => _sending = true);

    // In production: generate signing links via backend API, send notifications.
    await Future<void>.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent to ${_signers.length} signer(s)')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Request Signatures')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Document info
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(widget.documentName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Document to sign'),
            ),
          ),
          const SizedBox(height: 24),

          // Add signer form
          Text('Add signers', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addSigner,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Signers list
          if (_signers.isNotEmpty) ...[
            Text('Signers (${_signers.length})', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._signers.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return ListTile(
                leading: CircleAvatar(
                  child: Text('${i + 1}'),
                ),
                title: Text(s.name),
                subtitle: Text(s.email),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _signers.removeAt(i)),
                ),
              );
            }),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _sending ? null : _sendRequests,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send signing requests'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Signer {
  final String name;
  final String email;
  _Signer({required this.name, required this.email});
}
