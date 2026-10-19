import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context)!;
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
                    TextButton(onPressed: () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut), child: Text(l.bCommonBack)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == _totalPages - 1 ? l.getStarted : l.bCommonNext),
                  ),
                ],
              ),
            ),
            if (!_loadingVariant)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l.bOnboardVariant(_variant.id, _variant.name),
                    style: TextStyle(fontSize: 10, color: cs.outline)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _welcomePage(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    return _OnboardingPage(
      icon: Icons.privacy_tip_outlined,
      title: l.bOnboardWelcomeTitle,
      subtitle: l.bOnboardWelcomeSubtitle,
      bullets: [
        l.bOnboardWelcomeBullet1,
        l.bOnboardWelcomeBullet2,
        l.bOnboardWelcomeBullet3,
      ],
      color: AppColors.primary,
    );
  }

  Widget _aiSetupPage(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    return _OnboardingPage(
      icon: Icons.psychology_outlined,
      title: l.bOnboardAiTitle,
      subtitle: l.bOnboardAiSubtitle,
      bullets: [
        l.bOnboardAiBullet1,
        l.bOnboardAiBullet2,
        l.bOnboardAiBullet3,
      ],
      color: const Color(0xFF6366D8),
      cta: FilledButton.tonalIcon(
        onPressed: () => context.push('/settings'),
        icon: const Icon(Icons.key, size: 18),
        label: Text(l.bOnboardAiCta),
      ),
    );
  }

  Widget _profilePage(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    return _OnboardingPage(
      icon: Icons.badge_outlined,
      title: l.bOnboardProfileTitle,
      subtitle: l.bOnboardProfileSubtitle,
      bullets: [
        l.bOnboardProfileBullet1,
        l.bOnboardProfileBullet2,
        l.bOnboardProfileBullet3,
      ],
      color: const Color(0xFF2E9E7B),
      cta: FilledButton.icon(
        onPressed: () => context.push('/profile'),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(l.bOnboardProfileCta),
      ),
    );
  }

  Widget _firstDocPage(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    return _OnboardingPage(
      icon: Icons.folder_open_outlined,
      title: l.bOnboardDocTitle,
      subtitle: l.bOnboardDocSubtitle,
      bullets: [
        l.bOnboardDocBullet1,
        l.bOnboardDocBullet2,
        l.bOnboardDocBullet3,
      ],
      color: const Color(0xFF4C63D2),
      cta: FilledButton.icon(
        onPressed: () => context.push('/tools/pick-edit'),
        icon: const Icon(Icons.edit_document),
        label: Text(l.bOnboardDocCta),
      ),
    );
  }

  Widget _paywallABPage(ColorScheme cs) {
    final isA = _variant.id == 'A';
    final l = AppLocalizations.of(context)!;
    final bestValue = l.planBestValue.toUpperCase();
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
                      Text(isA ? l.bOnboardPaywallTitleA : l.bOnboardPaywallTitleB,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(isA ? l.bOnboardPaywallSubA : l.bOnboardPaywallSubB,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(l.bOnboardWhatYouGet,
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          for (final b in [
            l.bOnboardProBullet1,
            l.bOnboardProBullet2,
            l.bOnboardProBullet3,
            l.bOnboardProBullet4,
            l.bOnboardProBullet5,
            l.bOnboardProBullet6,
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // A/B variant cards
          _ABPlanCard(
            title: l.planYearly,
            price: l.bOnboardPricePerYear('€29.99'),
            badge: _variant.isBadge('yearly') ? bestValue : null,
            highlighted: _variant.isHighlighted('yearly'),
            onTap: () {
              _abService.trackConversion('yearly');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 12),
          _ABPlanCard(
            title: l.planMonthly,
            price: l.bOnboardPricePerMonth('€4.99'),
            badge: _variant.isBadge('monthly') ? bestValue : null,
            highlighted: _variant.isHighlighted('monthly'),
            onTap: () {
              _abService.trackConversion('monthly');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 12),
          _ABPlanCard(
            title: l.planLifetime,
            price: l.bOnboardPriceOnce('€79.99'),
            subtitle: l.planLifetimeSubtitle,
            badge: _variant.isBadge('lifetime') ? bestValue : null,
            highlighted: _variant.isHighlighted('lifetime'),
            onTap: () {
              _abService.trackConversion('lifetime');
              context.push('/paywall');
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(l.bOnboardVariantFooter(_variant.id),
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
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
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
          color: highlighted ? AppColors.primary.withValues(alpha: 0.08) : cs.surface,
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
