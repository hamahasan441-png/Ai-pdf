import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class FormReviewScreen extends ConsumerStatefulWidget {
  final String documentId;

  const FormReviewScreen({super.key, required this.documentId});

  @override
  ConsumerState<FormReviewScreen> createState() => _FormReviewScreenState();
}

class _FormReviewScreenState extends ConsumerState<FormReviewScreen> {
  List<Map<String, dynamic>> _fields = [];
  bool _isLoading = true;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadFormFields();
  }


  Future<void> _loadFormFields() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(
        '${AppConstants.documentsEndpoint}/${widget.documentId}',
      );
      final fields = (response.data['form_fields'] as List?) ?? [];
      setState(() {
        _fields = fields.cast<Map<String, dynamic>>();
        for (final field in _fields) {
          final id = field['id'] as String;
          _controllers[id] = TextEditingController(
            text: field['confirmed_value'] ?? field['suggested_value'] ?? '',
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Form Fields')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Form Fields'),
        actions: [
          FilledButton(
            onPressed: _saveAll,
            child: const Text('Save All'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _fields.isEmpty
          ? const Center(child: Text('No form fields detected'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _fields.length,
              itemBuilder: (context, index) {
                final field = _fields[index];
                final id = field['id'] as String;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field['field_label'] ?? field['field_name'] ?? 'Field',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _controllers[id],
                          decoration: InputDecoration(
                            hintText: 'Enter value...',
                            suffixIcon: field['confidence_score'] != null
                                ? Tooltip(
                                    message:
                                        'AI Confidence: ${((field['confidence_score'] as num) * 100).toInt()}%',
                                    child: const Icon(Icons.auto_awesome,
                                        size: 18),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _saveAll() async {
    final updates = <Map<String, String>>[];
    for (final field in _fields) {
      final id = field['id'] as String;
      final value = _controllers[id]?.text ?? '';
      updates.add({'field_id': id, 'confirmed_value': value});
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.put(
        '${AppConstants.documentsEndpoint}/${widget.documentId}/fields',
        data: {'fields': updates},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All fields saved!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save fields')),
        );
      }
    }
  }
}
