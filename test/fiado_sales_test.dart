import 'package:flutter_test/flutter_test.dart';
import 'package:pos_inventory_app/fiado_sales.dart';

void main() {
  final date = DateTime(2026, 11, 13, 9, 30);
  final items = <Map<String, dynamic>>[
    {'id': 12, 'product_name': 'Arroz', 'unit_price': 850.0, 'quantity': 2},
    {'id': 13, 'product_name': 'Leche', 'unit_price': 1200.0, 'quantity': 1},
  ];

  test('builds one report entry for every unit in the paid fiado', () {
    final records = buildFiadoSaleRecords(
      uid: 'user-1',
      email: 'CLIENTE@example.com',
      deviceId: 'device-1',
      fiadoId: 7,
      clientName: 'Cliente',
      items: items,
      date: date,
    );

    expect(records, hasLength(3));
    expect(records.map((record) => record.id).toSet(), hasLength(3));
    expect(records.map((record) => record.data['productName']), [
      'Arroz',
      'Arroz',
      'Leche',
    ]);
    expect(records.map((record) => record.data['price']), [
      850.0,
      850.0,
      1200.0,
    ]);
    expect(records.first.data['email'], 'cliente@example.com');
    expect(records.every((record) => record.data['date'] == date), isTrue);
    expect(records.every((record) => record.data['fiadoId'] == 7), isTrue);
    expect(
      records.every((record) => record.data['fiadoClientName'] == 'Cliente'),
      isTrue,
    );
    expect(
      records.fold<double>(
        0,
        (total, record) => total + (record.data['price']! as num).toDouble(),
      ),
      2900,
    );
  });

  test('uses stable, installation-specific document IDs for retries', () {
    List<FiadoSaleRecord> build(String deviceId) => buildFiadoSaleRecords(
      uid: 'user-1',
      email: 'cliente@example.com',
      deviceId: deviceId,
      fiadoId: 7,
      clientName: 'Cliente',
      items: items,
      date: date,
    );
    final firstAttempt = build('device-1');
    final retry = build('device-1');
    final otherInstallation = build('device-2');

    expect(
      firstAttempt.map((record) => record.id),
      retry.map((record) => record.id),
    );
    expect(
      firstAttempt
          .map((record) => record.id)
          .toSet()
          .intersection(otherInstallation.map((record) => record.id).toSet()),
      isEmpty,
    );
  });

  test('rejects invalid fiado sale items', () {
    expect(
      () => buildFiadoSaleRecords(
        uid: 'user-1',
        email: 'cliente@example.com',
        deviceId: 'device-1',
        fiadoId: 7,
        clientName: 'Cliente',
        items: [
          {'id': 12, 'product_name': 'Arroz', 'unit_price': -1, 'quantity': 1},
        ],
        date: date,
      ),
      throwsArgumentError,
    );
  });
}
