import 'package:flutter_test/flutter_test.dart';
import 'package:pos_inventory_app/sales_ticket_format.dart';

void main() {
  test('formats the neutral sales ticket with item subtotals and CR flag', () {
    final lines = formatSalesTicketLines(
      items: [
        {'name': 'Arroz', 'price': 7130.47, 'quantity': 1},
        {'name': 'Frijoles', 'price': 1250.4, 'quantity': 2},
      ],
      total: 9631.27,
      date: DateTime(2026, 11, 12, 19, 30),
    );

    expect(lines, [
      '🧾 TICKET DE COMPRA',
      'Fecha: 12/11/2026 19:30',
      '▪️ Arroz x1 - ₡7130.47',
      '▪️ Frijoles x2 - ₡2500.80',
      '👉 TOTAL A PAGAR: ₡9631.27',
      '¡Gracias por su compra! 🇨🇷',
    ]);
    expect(lines.join('\n'), isNot(contains('PULPERÍA')));
  });

  test('converts unsupported ticket symbols to printer-safe text', () {
    expect(
      formatTicketLineForPrinter('🧾 TICKET DE COMPRA'),
      'TICKET DE COMPRA',
    );
    expect(
      formatTicketLineForPrinter('▪️ Arroz x1 - ₡7130.47'),
      '- Arroz x1 - CRC 7130.47',
    );
    expect(
      formatTicketLineForPrinter('¡Gracias por su compra! 🇨🇷'),
      '¡Gracias por su compra! Costa Rica',
    );
  });
}
