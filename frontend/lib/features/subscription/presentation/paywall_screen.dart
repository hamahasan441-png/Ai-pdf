import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/theme/app_theme.dart';
import '../application/subscription_controller.dart';
import '../domain/entitlement.dart';

/// Material 3 paywall. Reads live product prices from Play and drives the
/// purchase / restore flows through [SubscriptionController]. Fully localized.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionControllerProvider);
    final controller = ref.read(subscriptionControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final ent = state.entitlement;
    final trialActive = ent.tier.isTrial && ent.isPro;
    final int trialDaysLeft = (trialActive && ent.expiry != null)
        ? (ent.expiry!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 3).toInt()
        : 0;

    final benefits = <String>[
      l10n.proBenefit1,
      l10n.proBenefit2,
      l10n.proBenefit3,
      l10n.proBenefit4,
      l10n.proBenefit5,
      l10n.proBenefit6,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Pdoczy Pro')),
      body: (state.isPro && !trialActive)
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
                      Text(l10n.proUnlockTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(l10n.proTagline, style: TextStyle(color: Colors.white.withOpacity(0.9))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ...benefits.map((b) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(Icons.check_circle, color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
                const SizedBox(height: 16),

                // Free trial (one-time) or active-trial banner.
                if (trialActive)
                  _InfoBanner(
                    icon: Icons.timer_outlined,
                    color: cs.primary,
                    text: l10n.trialActive(trialDaysLeft),
                  )
                else if (state.canStartTrial) ...[
                  FilledButton.icon(
                    onPressed: state.purchaseInProgress ? null : controller.startFreeTrial,
                    icon: const Icon(Icons.lock_open),
                    label: Text(l10n.startFreeTrial),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.trialTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),

                if (!state.storeAvailable && state.initialized)
                  _InfoBanner(icon: Icons.info_outline, color: cs.error, text: l10n.proStoreUnavailable)
                else if (state.loadingProducts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.products.isEmpty && state.initialized)
                  _InfoBanner(icon: Icons.storefront_outlined, color: cs.error, text: l10n.proNoPlans)
                else ...[
                  _PlanCard(
                    title: l10n.planYearly,
                    badge: l10n.planBestValue,
                    product: state.productById(ProductIds.yearly),
                    onBuy: state.purchaseInProgress ? null : controller.buy,
                    highlighted: true,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    title: l10n.planMonthly,
                    product: state.productById(ProductIds.monthly),
                    onBuy: state.purchaseInProgress ? null : controller.buy,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    title: l10n.planLifetime,
                    subtitle: l10n.planLifetimeSubtitle,
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
                    child: Text(l10n.restorePurchases),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.proRenewDisclaimer,
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
                  Flexible(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
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
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 72, color: AppColors.success),
            const SizedBox(height: 16),
            Text(l10n.proActiveTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              entitlement.isLifetime ? l10n.proActiveLifetime : l10n.proActiveSubscription,
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
