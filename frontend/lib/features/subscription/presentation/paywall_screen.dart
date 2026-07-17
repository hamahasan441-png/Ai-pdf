import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/theme/app_theme.dart';
import '../application/subscription_controller.dart';
import '../domain/entitlement.dart';

/// Material 3 paywall. Reads live product prices from Play and drives the
/// purchase / restore flows through [SubscriptionController].
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  static const _benefits = <String>[
    'Unlimited AI chat, summaries & translation',
    'Premium models (GPT-4o, Claude, Gemini)',
    'AI form auto-fill & data extraction',
    'Unlimited OCR on scanned PDFs',
    'Batch processing & large files',
    'No ads, priority processing',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);
    final controller = ref.read(subscriptionControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI PDF Pro')),
      body: state.isPro
          ? _ProActive(entitlement: state.entitlement)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // Hero
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspace_premium, color: Colors.white, size: 36),
                      const SizedBox(height: 12),
                      const Text('Unlock everything',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('One membership for all AI features across your documents.',
                          style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ..._benefits.map((b) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(Icons.check_circle, color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
                const SizedBox(height: 20),

                if (!state.storeAvailable && state.initialized)
                  _InfoBanner(
                    icon: Icons.info_outline,
                    color: cs.error,
                    text: 'In-app purchases are unavailable on this device / account. '
                        'Sign in to Google Play and try again.',
                  )
                else if (state.loadingProducts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.products.isEmpty && state.initialized)
                  _InfoBanner(
                    icon: Icons.storefront_outlined,
                    color: cs.error,
                    text: 'No plans available yet. Products must be created and active '
                        'in the Play Console (IDs: pro_monthly, pro_yearly, pro_lifetime).',
                  )
                else ...[
                  _PlanCard(
                    title: 'Yearly',
                    badge: 'Best value',
                    product: state.productById(ProductIds.yearly),
                    onBuy: state.purchaseInProgress ? null : controller.buy,
                    highlighted: true,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    title: 'Monthly',
                    product: state.productById(ProductIds.monthly),
                    onBuy: state.purchaseInProgress ? null : controller.buy,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    title: 'Lifetime',
                    subtitle: 'Pay once, own forever',
                    product: state.productById(ProductIds.lifetime),
                    onBuy: state.purchaseInProgress ? null : controller.buy,
                  ),
                ],

                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  _InfoBanner(icon: Icons.error_outline, color: cs.error, text: state.error!),
                ],

                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: state.purchaseInProgress ? null : controller.restore,
                    child: const Text('Restore purchases'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Subscriptions renew automatically until cancelled in Google Play. '
                  'Lifetime is a one-time purchase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final bool highlighted;
  final ProductDetails? product;
  final void Function(ProductDetails product)? onBuy;

  const _PlanCard({
    required this.title,
    required this.product,
    required this.onBuy,
    this.subtitle,
    this.badge,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final available = product != null && onBuy != null;
    final price = product?.price ?? '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primary.withOpacity(0.06) : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? AppColors.primary : cs.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                      child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(subtitle ?? price, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          FilledButton(
            onPressed: available ? () => onBuy!(product!) : null,
            child: Text(price),
          ),
        ],
      ),
    );
  }
}

class _ProActive extends StatelessWidget {
  final Entitlement entitlement;
  const _ProActive({required this.entitlement});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 72, color: AppColors.success),
            const SizedBox(height: 16),
            Text("You're on ${entitlement.tier.label}",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              entitlement.isLifetime
                  ? 'Lifetime access — thank you for supporting the app!'
                  : 'All Pro features are unlocked. Manage or cancel anytime in Google Play.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
      ]),
    );
  }
}
