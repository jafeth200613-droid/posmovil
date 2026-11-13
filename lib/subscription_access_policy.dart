import 'package:cloud_firestore/cloud_firestore.dart';

enum SubscriptionAccessState {
  allowed,
  missing,
  inactive,
  expired,
  clockRollback,
}

class SubscriptionAccessPolicy {
  const SubscriptionAccessPolicy._();

  static SubscriptionAccessState evaluate({
    required Map<String, dynamic>? data,
    required DateTime now,
    required DateTime? lastKnownTime,
  }) {
    if (lastKnownTime != null && now.isBefore(lastKnownTime)) {
      return SubscriptionAccessState.clockRollback;
    }
    if (data == null) return SubscriptionAccessState.missing;
    if (data['status'] != 'active') return SubscriptionAccessState.inactive;
    if (data['plan'] == 'lifetime') return SubscriptionAccessState.allowed;

    final expiresAt = data['expiresAt'];
    final expiration = switch (expiresAt) {
      Timestamp value => value.toDate(),
      DateTime value => value,
      _ => null,
    };
    if (expiration == null || !expiration.isAfter(now)) {
      return SubscriptionAccessState.expired;
    }
    return SubscriptionAccessState.allowed;
  }
}
