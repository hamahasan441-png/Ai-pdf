import 'package:dio/dio.dart';

import '../../../core/config/app_settings.dart';
import '../domain/entitlement.dart';

/// Result of a server-side purchase verification.
class ServerVerification {
  final bool valid;
  final ProTier tier;
  final DateTime? expiry;
  const ServerVerification(this.valid, this.tier, this.expiry);
}

/// Confirms a purchase with the managed backend (`POST /billing/verify`), which
/// checks it against the Google Play Developer API. This is the authoritative
/// entitlement; the local cache is only for UX.
class BillingVerifier {
  /// Returns the server verdict, or `null` when verification could not be
  /// performed (no backend configured / offline / error) so the caller can
  /// fall back to an optimistic local grant.
  Future<ServerVerification?> verify({
    required String productId,
    required String purchaseToken,
    required bool isSubscription,
  }) async {
    if (!AppSettings.instance.hasCustomServer) return null;
    if (purchaseToken.isEmpty) return null;
    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppSettings.instance.apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final resp = await dio.post('/billing/verify', data: {
        'product_id': productId,
        'purchase_token': purchaseToken,
        'is_subscription': isSubscription,
      });
      final data = (resp.data as Map);
      final valid = data['valid'] == true;
      final tierName = data['tier']?.toString() ?? 'free';
      final tier = ProTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => ProTier.free,
      );
      DateTime? expiry;
      final ms = data['expiry_millis'];
      if (ms is int && ms > 0) {
        expiry = DateTime.fromMillisecondsSinceEpoch(ms);
      }
      return ServerVerification(valid, tier, expiry);
    } catch (_) {
      return null; // fall back to optimistic local grant
    }
  }
}
