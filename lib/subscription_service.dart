import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fiado_sales.dart';

class SubscriptionService {
  SubscriptionService._();

  static const String adminEmail = 'jafeth200613@gmail.com';
  static const String sinpeNumber = '6484-6604';
  static const String whatsappNumber = '50664846604';
  static const int monthlyPrice = 800;
  static const int trialDays = 2;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static Future<String>? _fiadoSalesDeviceId;

  static bool isAdmin([User? user]) {
    final email = (user ?? _auth.currentUser)?.email?.toLowerCase();
    return email == adminEmail;
  }

  static Future<void> ensureUserDocument(User user) async {
    final reference = _firestore.collection('users').doc(user.uid);
    final snapshot = await reference.get();
    if (snapshot.exists) return;

    final now = DateTime.now();
    await reference.set({
      'email': user.email?.toLowerCase() ?? '',
      'plan': 'trial',
      'status': 'active',
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: trialDays))),
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true);
  }

  static Future<Map<String, dynamic>?> getCachedUserAccess(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _userAccessPreferencePrefix(uid);
    final status = preferences.getString('${prefix}status');
    final plan = preferences.getString('${prefix}plan');
    if (status == null || plan == null) return null;

    final data = <String, dynamic>{'status': status, 'plan': plan};
    final expiresAt = preferences.getInt('${prefix}expiresAt');
    if (expiresAt != null) {
      data['expiresAt'] = Timestamp.fromMillisecondsSinceEpoch(expiresAt);
    }
    return data;
  }

  static Future<DateTime?> getLastKnownUserAccessTime(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt(
      '${_userAccessPreferencePrefix(uid)}lastKnownTime',
    );
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  static Future<void> cacheUserAccess({
    required String uid,
    required Map<String, dynamic> data,
    required DateTime observedAt,
    required bool serverValidated,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _userAccessPreferencePrefix(uid);
    final status = data['status'];
    final plan = data['plan'];
    if (status is String) {
      await preferences.setString('${prefix}status', status);
    } else {
      await preferences.remove('${prefix}status');
    }
    if (plan is String) {
      await preferences.setString('${prefix}plan', plan);
    } else {
      await preferences.remove('${prefix}plan');
    }

    final expiresAt = data['expiresAt'];
    final expiration = switch (expiresAt) {
      Timestamp value => value.millisecondsSinceEpoch,
      DateTime value => value.millisecondsSinceEpoch,
      _ => null,
    };
    if (expiration == null) {
      await preferences.remove('${prefix}expiresAt');
    } else {
      await preferences.setInt('${prefix}expiresAt', expiration);
    }

    if (serverValidated) {
      await preferences.setInt(
        '${prefix}lastKnownTime',
        observedAt.millisecondsSinceEpoch,
      );
    }
  }

  static Future<void> clearCachedUserAccess(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _userAccessPreferencePrefix(uid);
    await preferences.remove('${prefix}status');
    await preferences.remove('${prefix}plan');
    await preferences.remove('${prefix}expiresAt');
  }

  static Future<void> recordLastKnownUserAccessTime(
    String uid,
    DateTime observedAt,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '${_userAccessPreferencePrefix(uid)}lastKnownTime';
    final previous = preferences.getInt(key);
    if (previous != null && observedAt.millisecondsSinceEpoch < previous) {
      return;
    }
    await preferences.setInt(key, observedAt.millisecondsSinceEpoch);
  }

  static String _userAccessPreferencePrefix(String uid) =>
      'subscription_access_${uid}_';

  static Future<void> submitSinpeRequest({
    required String uid,
    required String email,
  }) async {
    await _firestore.collection('subscriptionRequests').add({
      'uid': uid,
      'email': email.toLowerCase(),
      'status': 'pending',
      'requestedPlan': 'monthly',
      'amount': monthlyPrice,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> recordSale({
    required String uid,
    required String email,
    required String productName,
    required num price,
    required DateTime date,
  }) async {
    await _firestore.collection('salesHistory').add({
      'uid': uid,
      'email': email.toLowerCase(),
      'productName': productName,
      'price': price,
      'date': Timestamp.fromDate(date),
    });
  }

  static Future<void> recordSales({
    required String uid,
    required String email,
    required List<Map<String, dynamic>> items,
    required DateTime date,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('No hay productos para registrar en el historial.');
    }

    final normalizedEmail = email.toLowerCase();
    for (final item in items) {
      final quantity = item['quantity'];
      final price = item['price'];
      final productName = item['name']?.toString().trim() ?? '';
      if (quantity is! int ||
          quantity <= 0 ||
          price is! num ||
          !price.toDouble().isFinite ||
          price < 0 ||
          productName.isEmpty) {
        throw ArgumentError('El detalle de una venta no es válido.');
      }
    }

    var batch = _firestore.batch();
    var pendingWrites = 0;
    final commits = <Future<void>>[];
    for (final item in items) {
      final quantity = item['quantity'] as int;
      for (var unitIndex = 0; unitIndex < quantity; unitIndex++) {
        batch.set(_firestore.collection('salesHistory').doc(), {
          'uid': uid,
          'email': normalizedEmail,
          'productName': item['name'].toString().trim(),
          'price': item['price'],
          'date': Timestamp.fromDate(date),
        });
        pendingWrites++;
        if (pendingWrites == 450) {
          commits.add(batch.commit());
          batch = _firestore.batch();
          pendingWrites = 0;
        }
      }
    }
    if (pendingWrites > 0) {
      commits.add(batch.commit());
    }
    await Future.wait(commits);
  }

  static Future<void> recordFiadoSales({
    required int fiadoId,
    required String clientName,
    required List<Map<String, dynamic>> items,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para registrar la venta del fiado.');
    }

    final records = buildFiadoSaleRecords(
      uid: user.uid,
      email: user.email ?? '',
      deviceId: await _getFiadoSalesDeviceId(),
      fiadoId: fiadoId,
      clientName: clientName,
      items: items,
      date: DateTime.now(),
    );

    try {
      await _writeFiadoSaleRecords(records);
    } catch (error, stackTrace) {
      try {
        await _deleteFiadoSaleRecords(records);
      } catch (cleanupError) {
        throw StateError(
          'No se pudo completar el registro de la venta ($error) ni limpiar '
          'los registros parciales ($cleanupError).',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> deleteFiadoSales({
    required int fiadoId,
    required List<Map<String, dynamic>> items,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para eliminar la venta del fiado.');
    }
    if (items.isEmpty) return;

    final records = buildFiadoSaleRecords(
      uid: user.uid,
      email: user.email ?? '',
      deviceId: await _getFiadoSalesDeviceId(),
      fiadoId: fiadoId,
      clientName: '',
      items: items,
      date: DateTime.now(),
    );
    await _deleteFiadoSaleRecords(records);
  }

  static Future<String> _getFiadoSalesDeviceId() {
    final existing = _fiadoSalesDeviceId;
    if (existing != null) return existing;

    final pending = _loadFiadoSalesDeviceId();
    _fiadoSalesDeviceId = pending;
    return pending.catchError((Object error) {
      _fiadoSalesDeviceId = null;
      throw error;
    });
  }

  static Future<String> _loadFiadoSalesDeviceId() async {
    const preferenceKey = 'fiado_sales_device_id';
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(preferenceKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final deviceId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    if (!await preferences.setString(preferenceKey, deviceId)) {
      throw StateError(
        'No se pudo guardar el identificador de esta instalación.',
      );
    }
    return deviceId;
  }

  static Future<void> _writeFiadoSaleRecords(
    List<FiadoSaleRecord> records,
  ) async {
    final commits = <Future<void>>[];
    for (var offset = 0; offset < records.length; offset += 450) {
      final batch = _firestore.batch();
      final end = (offset + 450).clamp(0, records.length);
      for (final record in records.sublist(offset, end)) {
        batch.set(_firestore.collection('salesHistory').doc(record.id), {
          ...record.data,
          'date': Timestamp.fromDate(record.data['date']! as DateTime),
        });
      }
      commits.add(batch.commit());
    }
    await Future.wait(commits);
  }

  static Future<void> _deleteFiadoSaleRecords(
    List<FiadoSaleRecord> records,
  ) async {
    final commits = <Future<void>>[];
    for (var offset = 0; offset < records.length; offset += 450) {
      final batch = _firestore.batch();
      final end = (offset + 450).clamp(0, records.length);
      for (final record in records.sublist(offset, end)) {
        batch.delete(_firestore.collection('salesHistory').doc(record.id));
      }
      commits.add(batch.commit());
    }
    await Future.wait(commits);
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchSales() {
    return _firestore
        .collection('salesHistory')
        .orderBy('date', descending: true)
        .snapshots();
  }

  static Future<List<Map<String, dynamic>>> getSales({
    required DateTime start,
    required DateTime end,
    Source source = Source.serverAndCache,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para consultar las ventas.');
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('salesHistory')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true);
    if (!isAdmin(user)) {
      query = query.where('uid', isEqualTo: user.uid);
    }

    final snapshot = await query.get(GetOptions(source: source));
    return snapshot.docs.map((document) {
      return {...document.data(), 'firestoreId': document.id};
    }).toList();
  }

  static Future<void> deleteSale(String firestoreId) async {
    await _firestore.collection('salesHistory').doc(firestoreId).delete();
  }

  static Future<void> deleteAllSales() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para borrar el historial.');
    }

    Query<Map<String, dynamic>> query = _firestore.collection('salesHistory');
    if (!isAdmin(user)) {
      query = query.where('uid', isEqualTo: user.uid);
    }

    while (true) {
      final snapshot = await query.limit(500).get();
      if (snapshot.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingRequests() {
    return _firestore
        .collection('subscriptionRequests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchUsers() {
    return _firestore.collection('users').orderBy('email').snapshots();
  }

  static Future<void> approveMonthly({
    required String requestId,
    required String uid,
  }) async {
    final now = DateTime.now();
    final userReference = _firestore.collection('users').doc(uid);
    final userSnapshot = await userReference.get();
    final data = userSnapshot.data();
    var base = now;

    final expiresAt = data?['expiresAt'];
    if (data?['plan'] == 'monthly' &&
        expiresAt is Timestamp &&
        expiresAt.toDate().isAfter(now)) {
      base = expiresAt.toDate();
    }

    await _firestore.runTransaction((transaction) async {
      transaction.update(userReference, {
        'plan': 'monthly',
        'status': 'active',
        'expiresAt': Timestamp.fromDate(base.add(const Duration(days: 30))),
      });
      transaction.update(
        _firestore.collection('subscriptionRequests').doc(requestId),
        {'status': 'approved', 'processedAt': FieldValue.serverTimestamp()},
      );
    });
  }

  static Future<void> approveLifetime({
    required String requestId,
    required String uid,
  }) async {
    await _firestore.runTransaction((transaction) async {
      transaction.update(_firestore.collection('users').doc(uid), {
        'plan': 'lifetime',
        'status': 'active',
        'expiresAt': FieldValue.delete(),
      });
      transaction.update(
        _firestore.collection('subscriptionRequests').doc(requestId),
        {'status': 'approved', 'processedAt': FieldValue.serverTimestamp()},
      );
    });
  }

  static Future<void> rejectRequest(String requestId) async {
    await _firestore.collection('subscriptionRequests').doc(requestId).update({
      'status': 'rejected',
      'processedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setLifetime(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'plan': 'lifetime',
      'status': 'active',
      'expiresAt': FieldValue.delete(),
    });
  }

  static Future<void> setMonthly(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'plan': 'monthly',
      'status': 'active',
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ),
    });
  }

  static Future<void> extendMonth(String uid) async {
    final reference = _firestore.collection('users').doc(uid);
    final snapshot = await reference.get();
    final data = snapshot.data();
    var base = DateTime.now();
    final expiresAt = data?['expiresAt'];
    if (data?['plan'] == 'monthly' &&
        expiresAt is Timestamp &&
        expiresAt.toDate().isAfter(base)) {
      base = expiresAt.toDate();
    }

    await reference.update({
      'plan': 'monthly',
      'status': 'active',
      'expiresAt': Timestamp.fromDate(base.add(const Duration(days: 30))),
    });
  }

  static Future<void> blockUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({'status': 'blocked'});
  }
}
