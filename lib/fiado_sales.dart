import 'dart:convert';

import 'package:crypto/crypto.dart';

class FiadoSaleRecord {
  const FiadoSaleRecord({required this.id, required this.data});

  final String id;
  final Map<String, Object> data;
}

List<FiadoSaleRecord> buildFiadoSaleRecords({
  required String uid,
  required String email,
  required String deviceId,
  required int fiadoId,
  required String clientName,
  required List<Map<String, dynamic>> items,
  required DateTime date,
}) {
  if (uid.isEmpty || deviceId.isEmpty || fiadoId <= 0) {
    throw ArgumentError('Faltan datos para identificar la cuenta fiada.');
  }

  final records = <FiadoSaleRecord>[];
  for (final item in items) {
    final itemId = item['id'];
    final rawQuantity = item['quantity'];
    final rawPrice = item['unit_price'];
    final productName = item['product_name']?.toString().trim() ?? '';
    if (itemId is! int ||
        itemId <= 0 ||
        rawQuantity is! num ||
        rawPrice is! num ||
        productName.isEmpty) {
      throw ArgumentError('El detalle de un producto fiado no es válido.');
    }

    final quantity = rawQuantity.toInt();
    final unitPrice = rawPrice.toDouble();
    if (quantity <= 0 || !unitPrice.isFinite || unitPrice < 0) {
      throw ArgumentError('Hay una cantidad o precio inválido en el fiado.');
    }

    for (var unitIndex = 0; unitIndex < quantity; unitIndex++) {
      final identity = '$uid|$deviceId|$fiadoId|$itemId|$unitIndex';
      final documentId = 'fiado_${sha256.convert(utf8.encode(identity))}';
      records.add(
        FiadoSaleRecord(
          id: documentId,
          data: {
            'uid': uid,
            'email': email.toLowerCase(),
            'productName': productName,
            'price': unitPrice,
            'date': date,
            'fiadoId': fiadoId,
            'fiadoItemId': itemId,
            'fiadoClientName': clientName,
          },
        ),
      );
    }
  }

  if (records.isEmpty) {
    throw ArgumentError('La cuenta no tiene productos para registrar.');
  }
  return records;
}
