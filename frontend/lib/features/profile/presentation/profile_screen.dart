import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(AppConstants.profileEndpoint);
      final data = response.data;
      _firstNameCtrl.text = data['first_name'] ?? '';
      _lastNameCtrl.text = data['last_name'] ?? '';
      _phoneCtrl.text = data['phone'] ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _cityCtrl.text = data['city'] ?? '';
      _stateCtrl.text = data['state'] ?? '';
      _zipCtrl.text = data['zip_code'] ?? '';
      _countryCtrl.text = data['country'] ?? '';
      _dobCtrl.text = data['date_of_birth'] ?? '';
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.put(AppConstants.profileEndpoint, data: {
        'first_name': _firstNameCtrl.text,
        'last_name': _lastNameCtrl.text,
        'phone': _phoneCtrl.text,
        'address': _addressCtrl.text,
        'city': _cityCtrl.text,
        'state': _stateCtrl.text,
        'zip_code': _zipCtrl.text,
        'country': _countryCtrl.text,
        'date_of_birth': _dobCtrl.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved!')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile')),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _countryCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          FilledButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personal Information',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildField('First Name', _firstNameCtrl),
              _buildField('Last Name', _lastNameCtrl),
              _buildField('Phone', _phoneCtrl),
              _buildField('Date of Birth', _dobCtrl),
              const SizedBox(height: 24),
              Text('Address',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildField('Street Address', _addressCtrl),
              _buildField('City', _cityCtrl),
              _buildField('State', _stateCtrl),
              _buildField('ZIP Code', _zipCtrl),
              _buildField('Country', _countryCtrl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
