import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_pdf/core/services/onboarding_service.dart';
import 'package:ai_pdf/core/services/paywall_ab_service.dart';
import 'package:ai_pdf/core/theme/app_theme.dart';

/// Onboarding Screen — E6.2 Paywall A/B + Enhanced Onboarding.
///
/// Flow:
/// 1. Welcome — app overview + key value props (privacy-first, offline, AI)
/// 2. AI Setup — explain BYO-key vs managed AI, show 3-day trial benefit
/// 3. Profile — set up personal data for auto-fill (optional)
/// 4. First document — guide to open/edit/export + paywall variant A/B
/// 5. Paywall — variant A (monthly emphasis) vs B (lifetime emphasis), tracks exposure + conversion
///
/// Tracks via PaywallABService + AnalyticsService (future Firebase).
/// Local remote config JSON can override variant (see app_config.dart).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  PaywallVariant _variant = PaywallVariant.a;
  bool _loadingVariant = true;
  final _onboardingService = const OnboardingService();
  final _abService = const PaywallABService();

  static const int _totalPages = 5;

  @override
  void initState() {
    super.initState();
    _loadVariant();
  }

  Future<void> _loadVariant() async {
    final v = await _abService.getVariant();
    await _abService.trackExposure();
    setState(() {
      _variant = v;
      _loadingVariant = false;
    });
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  void _finish() async {
    await _onboardingService.markCompleted();
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_page + 1) / _totalPages,
              backgroundColor: cs.surfaceContainerHighest,
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _welcomePage(cs),
                  _aiSetupPage(cs),
                  _profilePage(cs),
                  _firstDocPage(cs),
                  _paywallABPage(cs),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(onPressed: () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut), child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == _totalPages - 1 ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
            if (!_loadingVariant)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Variant ${_variant.id}: ${_variant.name}',
                    style: TextStyle(fontSize: 10, color: cs.outline)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _welcomePage(ColorScheme cs) {
    return _OnboardingPage(
      icon: Icons.privacy_tip_outlined,
      title: 'Private, Offline, AI-Powered',
      subtitle: 'Edit, sign, and understand PDFs — with on-device AI that never uploads your files. Your data stays on your phone.',
      bullets: const [
        'Offline tools: compress, merge, split, OCR, watermark — no internet needed',
        'On-device AI: BM25 RAG + ML Kit OCR — page-cited answers, no cloud',
        'Profile auto-fill: 100+ field types, 12+ languages, encrypted on device',
      ],
      color: AppColors.primary,
    );
  }

  Widget _aiSetupPage(ColorScheme cs) {
    return _OnboardingPage(
      icon: Icons.psychology_outlined,
      title: 'Two Ways to Use AI',
      subtitle: 'Choose what works for you — both are private by default.',
      bullets: const [
        'BYO-Key (free): Paste your OpenRouter key — direct, no server, your quota',
        'Managed AI (Pro): No key needed, metered via backend, 3-day free trial, unlimited when Pro — server holds provider keys, you get zero-setup AI',
        'Free tier: all offline tools + 15 managed AI calls/day — genuinely useful',
      ],
      color: const Color(0xFF6366D8),
      cta: FilledButton.tonalIcon(
        onPressed: () => context.push('/settings'),
        icon: const Icon(Icons.key, size: 18),
        label: const Text('Set up AI key (optional)'),
      ),
    );
  }

  Widget _profilePage(ColorScheme cs) {
    return _OnboardingPage(
      icon: Icons.badge_outlined,
      title: 'Set Up Your Profile Once',
      subtitle: 'Save your personal data encrypted on device — name, address, DOB, ID — and auto-fill any form with one tap.',
      bullets: const [
        'Encrypted with Fernet at rest, never leaves device',
        'Matches 100+ field labels across German, English, French, Spanish, Arabic, Kurdish',
        'Fill from ID doc: upload passport/certificate/CV, OCR on-device, match + review + place',
      ],
      color: const Color(0xFF2E9E7B),
      cta: FilledButton.icon(
        onPressed: () => context.push('/profile'),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Set up profile'),
      ),
    );
  }

  Widget _firstDocPage(ColorScheme cs) {
    return _OnboardingPage(
      icon: Icons.folder_open_outlined,
      title: 'Open Your First Document',
      subtitle: 'Pick a PDF or image, edit inline, add signatures, and export a searchable PDF.',
      bullets: const [
        'Inline text editor with caret + per-run bold/italic/underline',
        'Snap guides, grouping, layer reorder, revision history, crash recovery',
        'Export fidelity: Latin + Arabic/Kurdish searchable when font asset present',
      ],
      color: const Color(0xFF4C63D2),
      cta: FilledButton.icon(
        onPressed: () => context.push('/tools/pick-edit'),
        icon: const Icon(Icons.edit_document),
        label: const Text('Open editor'),
      ),
    );
  }

  Widget _paywallABPage(ColorScheme cs) {
    final isA = _variant.id == 'A';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isA ? 'Unlock Pro — Monthly Highlighted' : 'Unlock Pro — Lifetime Best Value',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(isA ? 'Variant A: flexible monthly, yearly best value' : 'Variant B: pay once, own forever — experimental',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('What you get with Pro:',
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          for (final b in [
            'Unlimited managed AI — no key needed, zero-setup',
            'No ads — banner only on browse for free, zero for Pro',
            'PDF→Word/Excel/PowerPoint conversion (server-side)',
            '3-day free trial — unlocks everything',
            'Cloud sync opt-in encrypted (E8.2) — annotations across devices',
            'Per-team AI quotas + SSO for enterprise (E8.1+E5.3)',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // A/B variant cards
          _ABPlanCard(
            title: 'Yearly',
            price: '€29.99/year',
            badge: _variant.isBadge('yearly') ? 'BEST VALUE' : null,
            highlighted: _variant.isHighlighted('yearly'),
            onTap: () {
              _abService.trackConversion('yearly');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 12),
          _ABPlanCard(
            title: 'Monthly',
            price: '€4.99/month',
            badge: _variant.isBadge('monthly') ? 'BEST VALUE' : null,
            highlighted: _variant.isHighlighted('monthly'),
            onTap: () {
              _abService.trackConversion('monthly');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 12),
          _ABPlanCard(
            title: 'Lifetime',
            price: '€79.99 once',
            subtitle: 'Pay once, own forever',
            badge: _variant.isBadge('lifetime') ? 'BEST VALUE' : null,
            highlighted: _variant.isHighlighted('lifetime'),
            onTap: () {
              _abService.trackConversion('lifetime');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Variant ${_variant.id} • A/B test exposure tracked • Conversion measured',
                style: TextStyle(fontSize: 10, color: cs.outline)),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final Color color;
  final Widget? cta;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.color,
    this.cta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 36),
          ),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          if (cta != null) ...[
            const SizedBox(height: 24),
            cta!,
          ],
        ],
      ),
    );
  }
}

class _ABPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? subtitle;
  final String? badge;
  final bool highlighted;
  final VoidCallback onTap;

  const _ABPlanCard({
    required this.title,
    required this.price,
    this.subtitle,
    this.badge,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primary.withOpacity(0.08) : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlighted ? AppColors.primary : cs.outlineVariant, width: highlighted ? 2 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                          child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Text(price, style: TextStyle(fontWeight: FontWeight.w700, color: highlighted ? AppColors.primary : cs.onSurface)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}
