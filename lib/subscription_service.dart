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
    return _firestore.collection('users').doc(uid).snapshots();
  }

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
    for (var offset = 0; offset < records.length; offset += 450) {
      final batch = _firestore.batch();
      final end = (offset + 450).clamp(0, records.length);
      for (final record in records.sublist(offset, end)) {
        batch.set(_firestore.collection('salesHistory').doc(record.id), {
          ...record.data,
          'date': Timestamp.fromDate(record.data['date']! as DateTime),
        });
      }
      await batch.commit();
    }
  }

  static Future<void> _deleteFiadoSaleRecords(
    List<FiadoSaleRecord> records,
  ) async {
    for (var offset = 0; offset < records.length; offset += 450) {
      final batch = _firestore.batch();
      final end = (offset + 450).clamp(0, records.length);
      for (final record in records.sublist(offset, end)) {
        batch.delete(_firestore.collection('salesHistory').doc(record.id));
      }
      await batch.commit();
    }
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

    final snapshot = await query.get();
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
