import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/features/subscription/application/subscription_controller.dart';
import 'package:ai_pdf/features/subscription/data/entitlement_store.dart';
import 'package:ai_pdf/features/subscription/data/purchase_service.dart';

class _FakeStore implements PurchaseService {
  final bool available;
  var restores = 0;
  final _updates = StreamController<List<PurchaseDetails>>.broadcast();

  _FakeStore({required this.available});

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _updates.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProducts() async =>
      ProductDetailsResponse(productDetails: const [], notFoundIDs: const []);

  @override
  Future<void> restore() async => restores++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each launch asks the store for owned purchases, so renewals keep Pro', () async {
    final store = _FakeStore(available: true);
    final controller = SubscriptionController(store, EntitlementStore());
    await controller.init();
    expect(store.restores, 1);
  });

  test('no store, no request', () async {
    final store = _FakeStore(available: false);
    final controller = SubscriptionController(store, EntitlementStore());
    await controller.init();
    expect(store.restores, 0);
  });
}
