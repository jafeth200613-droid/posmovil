enum SalesReportPeriod { day, week, month }

class SalesReportBucket {
  const SalesReportBucket({required this.label, required this.revenue});

  final String label;
  final double revenue;
}

class ProductSalesSummary {
  const ProductSalesSummary({
    required this.name,
    required this.unitsSold,
    required this.revenue,
  });

  final String name;
  final int unitsSold;
  final double revenue;
}

class SalesReportData {
  const SalesReportData({
    required this.period,
    required this.start,
    required this.end,
    required this.totalIncome,
    required this.unitsSold,
    required this.buckets,
    required this.topProducts,
  });

  final SalesReportPeriod period;
  final DateTime start;
  final DateTime end;
  final double totalIncome;
  final int unitsSold;
  final List<SalesReportBucket> buckets;
  final List<ProductSalesSummary> topProducts;

  factory SalesReportData.fromSales({
    required List<Map<String, dynamic>> sales,
    required SalesReportPeriod period,
    required DateTime now,
  }) {
    final start = periodStart(period, now);
    final end = periodEnd(period, start);
    final bucketLabels = _bucketLabels(period);
    final bucketRevenue = List<double>.filled(bucketLabels.length, 0);
    final productUnits = <String, int>{};
    final productRevenue = <String, double>{};
    var totalIncome = 0.0;
    var unitsSold = 0;

    for (final sale in sales) {
      final parsedDate = DateTime.tryParse(sale['date']?.toString() ?? '');
      final rawPrice = sale['price'];
      if (parsedDate == null || rawPrice is! num) continue;

      final saleDate = parsedDate.toLocal();
      if (saleDate.isBefore(start) || !saleDate.isBefore(end)) continue;

      final price = rawPrice.toDouble();
      final productName = sale['product_name']?.toString().trim();
      final name = productName == null || productName.isEmpty
          ? 'Producto sin nombre'
          : productName;
      final bucketIndex = _bucketIndex(period, saleDate);

      totalIncome += price;
      unitsSold++;
      bucketRevenue[bucketIndex] += price;
      productUnits.update(name, (count) => count + 1, ifAbsent: () => 1);
      productRevenue.update(
        name,
        (revenue) => revenue + price,
        ifAbsent: () => price,
      );
    }

    final topProducts = productUnits.keys.map((name) {
      return ProductSalesSummary(
        name: name,
        unitsSold: productUnits[name]!,
        revenue: productRevenue[name]!,
      );
    }).toList()
      ..sort((left, right) {
        final unitsComparison = right.unitsSold.compareTo(left.unitsSold);
        return unitsComparison != 0
            ? unitsComparison
            : right.revenue.compareTo(left.revenue);
      });

    return SalesReportData(
      period: period,
      start: start,
      end: end,
      totalIncome: totalIncome,
      unitsSold: unitsSold,
      buckets: [
        for (var index = 0; index < bucketLabels.length; index++)
          SalesReportBucket(
            label: bucketLabels[index],
            revenue: bucketRevenue[index],
          ),
      ],
      topProducts: topProducts.take(5).toList(),
    );
  }

  static DateTime periodStart(SalesReportPeriod period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      SalesReportPeriod.day => today,
      SalesReportPeriod.week => today.subtract(Duration(days: today.weekday - 1)),
      SalesReportPeriod.month => DateTime(now.year, now.month),
    };
  }

  static DateTime periodEnd(SalesReportPeriod period, DateTime start) {
    return switch (period) {
      SalesReportPeriod.day => start.add(const Duration(days: 1)),
      SalesReportPeriod.week => start.add(const Duration(days: 7)),
      SalesReportPeriod.month => DateTime(start.year, start.month + 1),
    };
  }

  static List<String> _bucketLabels(SalesReportPeriod period) {
    return switch (period) {
      SalesReportPeriod.day => const [
        '00',
        '03',
        '06',
        '09',
        '12',
        '15',
        '18',
        '21',
      ],
      SalesReportPeriod.week => const [
        'Lun',
        'Mar',
        'Mié',
        'Jue',
        'Vie',
        'Sáb',
        'Dom',
      ],
      SalesReportPeriod.month => const [
        'Sem 1',
        'Sem 2',
        'Sem 3',
        'Sem 4',
        'Sem 5',
      ],
    };
  }

  static int _bucketIndex(SalesReportPeriod period, DateTime saleDate) {
    return switch (period) {
      SalesReportPeriod.day => saleDate.hour ~/ 3,
      SalesReportPeriod.week => saleDate.weekday - 1,
      SalesReportPeriod.month => (saleDate.day - 1) ~/ 7,
    };
  }
}
