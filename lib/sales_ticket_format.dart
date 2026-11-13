import 'package:intl/intl.dart';

import 'currency_format.dart';

List<String> formatSalesTicketLines({
  required List<Map<String, dynamic>> items,
  required num total,
  required DateTime date,
}) {
  return [
    '🧾 TICKET DE COMPRA',
    'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(date)}',
    for (final item in items)
      '▪️ ${item['name']} x${(item['quantity'] as num).toInt()} - '
          '₡${formatMoney((item['price'] as num) * (item['quantity'] as num))}',
    '👉 TOTAL A PAGAR: ₡${formatMoney(total)}',
    '¡Gracias por su compra! 🇨🇷',
  ];
}

String formatTicketLineForPrinter(String line) => line
    .replaceFirst('🧾 ', '')
    .replaceFirst('▪️ ', '- ')
    .replaceFirst('👉 ', '')
    .replaceFirst('🇨🇷', 'Costa Rica')
    .replaceAll('₡', 'CRC ')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');
