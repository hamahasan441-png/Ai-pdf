import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); _email.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post(AppConstants.registerEndpoint, data: {
        'email': _email.text.trim(),
        'password': _pass.text,
        'full_name': _name.text.trim(),
      });
      // Auto-login
      final r = await api.dio.post(AppConstants.loginEndpoint, data: {
        'email': _email.text.trim(),
        'password': _pass.text,
      });
      await api.saveTokens(r.data['access_token'], r.data['refresh_token']);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = 'Registration failed. Try a different email.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/login'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(children: [
              Text('Create Account', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Fill forms smarter with AI', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 32),
              if (_error != null)
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                ),
              TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outlined)), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
              const SizedBox(height: 14),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)), validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null),
              const SizedBox(height: 14),
              TextFormField(controller: _pass, obscureText: true, textInputAction: TextInputAction.done, onFieldSubmitted: (_) => _register(), decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outlined)), validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50, child: FilledButton(
                onPressed: _loading ? null : _register,
                child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Account', style: TextStyle(fontSize: 16)),
              )),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Already have an account?'),
                TextButton(onPressed: () => context.go('/login'), child: const Text('Sign In')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
