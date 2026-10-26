import 'package:flutter_test/flutter_test.dart';
import 'package:pos_inventory_app/sales_report_data.dart';

void main() {
  final now = DateTime(2026, 10, 25, 14, 30);

  final sales = <Map<String, dynamic>>[
    {'product_name': 'Café', 'price': 100.0, 'date': '2026-10-25 00:10'},
    {'product_name': 'Café', 'price': 50.0, 'date': '2026-10-25 14:20'},
    {'product_name': 'Arroz', 'price': 80.0, 'date': '2026-10-19 10:00'},
    {'product_name': 'Arroz', 'price': 60.0, 'date': '2026-10-24 18:00'},
    {'product_name': 'Leche', 'price': 40.0, 'date': '2026-10-26 09:00'},
    {'product_name': 'Leche', 'price': 30.0, 'date': '2026-11-01 09:00'},
    {'product_name': 'Inválida', 'price': 999.0, 'date': 'fecha inválida'},
  ];

  test('daily report totals today and groups sales by three-hour blocks', () {
    final report = SalesReportData.fromSales(
      sales: sales,
      period: SalesReportPeriod.day,
      now: now,
    );

    expect(report.totalIncome, 150);
    expect(report.unitsSold, 2);
    expect(report.buckets, hasLength(8));
    expect(report.buckets[0].revenue, 100);
    expect(report.buckets[4].revenue, 50);
    expect(report.topProducts.single.name, 'Café');
  });

  test('weekly report starts on Monday and excludes the next Monday', () {
    final report = SalesReportData.fromSales(
      sales: sales,
      period: SalesReportPeriod.week,
      now: now,
    );

    expect(report.start, DateTime(2026, 10, 19));
    expect(report.end, DateTime(2026, 10, 26));
    expect(report.totalIncome, 290);
    expect(report.unitsSold, 4);
    expect(report.buckets[0].revenue, 80);
    expect(report.buckets[5].revenue, 60);
    expect(report.buckets[6].revenue, 150);
  });

  test('monthly report includes only the selected month and ranks products', () {
    final report = SalesReportData.fromSales(
      sales: sales,
      period: SalesReportPeriod.month,
      now: now,
    );

    expect(report.start, DateTime(2026, 10));
    expect(report.end, DateTime(2026, 11));
    expect(report.totalIncome, 330);
    expect(report.unitsSold, 5);
    expect(report.buckets, hasLength(5));
    expect(report.topProducts.map((product) => product.name).toList(), [
      'Café',
      'Arroz',
      'Leche',
    ]);
    expect(report.topProducts.first.unitsSold, 2);
  });
}
