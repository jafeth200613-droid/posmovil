import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_inventory_app/subscription_access_policy.dart';
import 'package:pos_inventory_app/subscription_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SubscriptionAccessPolicy', () {
    final now = DateTime(2026, 11, 13, 12);

    test('allows an active subscription before its exact expiry time', () {
      final result = SubscriptionAccessPolicy.evaluate(
        data: {
          'status': 'active',
          'plan': 'trial',
          'expiresAt': Timestamp.fromDate(now.add(const Duration(seconds: 1))),
        },
        now: now,
        lastKnownTime: now,
      );

      expect(result, SubscriptionAccessState.allowed);
    });

    test('blocks at the exact expiry time', () {
      final result = SubscriptionAccessPolicy.evaluate(
        data: {
          'status': 'active',
          'plan': 'monthly',
          'expiresAt': Timestamp.fromDate(now),
        },
        now: now,
        lastKnownTime: now,
      );

      expect(result, SubscriptionAccessState.expired);
    });

    test('blocks subscriptions with a non-active status', () {
      final result = SubscriptionAccessPolicy.evaluate(
        data: {
          'status': 'blocked',
          'plan': 'monthly',
          'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 30))),
        },
        now: now,
        lastKnownTime: now,
      );

      expect(result, SubscriptionAccessState.inactive);
    });

    test('allows active lifetime access without an expiry', () {
      final result = SubscriptionAccessPolicy.evaluate(
        data: {'status': 'active', 'plan': 'lifetime'},
        now: now,
        lastKnownTime: now,
      );

      expect(result, SubscriptionAccessState.allowed);
    });

    test(
      'blocks when the device clock is earlier than the last known time',
      () {
        final result = SubscriptionAccessPolicy.evaluate(
          data: {
            'status': 'active',
            'plan': 'trial',
            'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
          },
          now: now.subtract(const Duration(minutes: 1)),
          lastKnownTime: now,
        );

        expect(result, SubscriptionAccessState.clockRollback);
      },
    );

    test('fails closed when no cached subscription exists', () {
      final result = SubscriptionAccessPolicy.evaluate(
        data: null,
        now: now,
        lastKnownTime: null,
      );

      expect(result, SubscriptionAccessState.missing);
    });
  });

  group('SubscriptionService local subscription cache', () {
    test(
      'stores status, plan, exact expiry and server validation time',
      () async {
        final expiresAt = DateTime(2026, 11, 15, 9, 30);
        final observedAt = DateTime(2026, 11, 13, 12);

        await SubscriptionService.cacheUserAccess(
          uid: 'user-a',
          data: {
            'status': 'active',
            'plan': 'trial',
            'expiresAt': Timestamp.fromDate(expiresAt),
          },
          observedAt: observedAt,
          serverValidated: true,
        );

        final cached = await SubscriptionService.getCachedUserAccess('user-a');
        final lastKnownTime =
            await SubscriptionService.getLastKnownUserAccessTime('user-a');
        expect(cached?['status'], 'active');
        expect(cached?['plan'], 'trial');
        expect((cached?['expiresAt'] as Timestamp).toDate(), expiresAt);
        expect(lastKnownTime, observedAt);
      },
    );

    test('does not move the saved time backwards', () async {
      final firstTime = DateTime(2026, 11, 13, 12);
      await SubscriptionService.recordLastKnownUserAccessTime(
        'user-a',
        firstTime,
      );

      await SubscriptionService.recordLastKnownUserAccessTime(
        'user-a',
        firstTime.subtract(const Duration(minutes: 1)),
      );

      expect(
        await SubscriptionService.getLastKnownUserAccessTime('user-a'),
        firstTime,
      );
    });

    test('keeps cached subscriptions isolated by account', () async {
      await SubscriptionService.cacheUserAccess(
        uid: 'user-a',
        data: {'status': 'active', 'plan': 'lifetime'},
        observedAt: DateTime(2026, 11, 13, 12),
        serverValidated: true,
      );

      expect(await SubscriptionService.getCachedUserAccess('user-b'), isNull);
    });
  });
}
