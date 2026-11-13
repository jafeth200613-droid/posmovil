import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'database_helper.dart';
import 'sales_report_data.dart';
import 'subscription_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  SalesReportPeriod _period = SalesReportPeriod.day;
  bool _loading = true;
  String? _loadError;
  final TextEditingController _searchController = TextEditingController();
  DateTime _rangeStart = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _rangeEnd = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day + 1,
  );

  static final _currencyFormat = NumberFormat.currency(
    locale: 'es_CR',
    symbol: '₡',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _cargarVentas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarVentas() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final sales = await SubscriptionService.getSales(
        start: _rangeStart,
        end: _rangeEnd,
      );
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  SalesReportData get _report => SalesReportData.fromSales(
    sales: _sales,
    period: _period,
    now: DateTime.now(),
    start: _rangeStart,
    end: _rangeEnd,
  );

  List<Map<String, dynamic>> get _filteredSales {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _sales;
    return _sales.where((sale) {
      final name = (sale['productName'] ?? sale['product_name'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(query);
    }).toList();
  }

  String _formatCurrency(num amount) => _currencyFormat.format(amount);

  String _periodDescription(SalesReportData report) {
    final lastDay = report.end.subtract(const Duration(days: 1));
    final start = DateFormat('dd/MM/yyyy').format(report.start);
    final end = DateFormat('dd/MM/yyyy').format(lastDay);
    return _period == SalesReportPeriod.day ? start : '$start - $end';
  }

  Future<void> _selectPeriod(SalesReportPeriod period) async {
    final today = DateTime.now();
    DateTime? start;
    DateTime? end;

    if (period == SalesReportPeriod.day) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _rangeStart,
        firstDate: DateTime(2000),
        lastDate: DateTime(today.year, today.month, today.day),
      );
      if (selectedDate == null || !mounted) return;
      start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      end = start.add(const Duration(days: 1));
    } else {
      final initialStart = period == SalesReportPeriod.week
          ? _rangeStart.subtract(Duration(days: _rangeStart.weekday - 1))
          : DateTime(_rangeStart.year, _rangeStart.month);
      final initialEnd = period == SalesReportPeriod.week
          ? initialStart.add(const Duration(days: 6))
          : DateTime(
              initialStart.year,
              initialStart.month + 1,
            ).subtract(const Duration(days: 1));
      final selectedRange = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(
          start: initialStart,
          end: initialEnd.isAfter(today) ? today : initialEnd,
        ),
        firstDate: DateTime(2000),
        lastDate: DateTime(today.year, today.month, today.day),
        helpText: period == SalesReportPeriod.week
            ? 'Selecciona la semana'
            : 'Selecciona el rango del mes',
      );
      if (selectedRange == null || !mounted) return;
      start = DateTime(
        selectedRange.start.year,
        selectedRange.start.month,
        selectedRange.start.day,
      );
      end = DateTime(
        selectedRange.end.year,
        selectedRange.end.month,
        selectedRange.end.day + 1,
      );
    }

    setState(() {
      _period = period;
      _rangeStart = start!;
      _rangeEnd = end!;
    });
    await _cargarVentas();
  }

  void _confirmarBorrarHistorial() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Borrar historial?'),
        content: const Text(
          'Esta acción eliminará todos los registros de ventas. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await SubscriptionService.deleteAllSales();
              await DatabaseHelper.instance.deleteAllSales();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              await _cargarVentas();
            },
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarVenta(Map<String, dynamic> sale) async {
    final firestoreId = sale['firestoreId']?.toString();
    if (firestoreId == null) return;
    await SubscriptionService.deleteSale(firestoreId);
    if (!mounted) return;
    setState(
      () => _sales.removeWhere((item) => item['firestoreId'] == firestoreId),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Venta eliminada del historial')),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          border: Border.all(color: Colors.indigo.shade100),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: Colors.indigo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.indigo,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueChart(SalesReportData report) {
    final maxRevenue = report.buckets.fold<double>(
      0,
      (maximum, bucket) => math.max(maximum, bucket.revenue),
    );
    final chartMaxY = maxRevenue == 0 ? 1.0 : maxRevenue * 1.2;
    final yInterval = chartMaxY / 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (_period) {
          SalesReportPeriod.day => 'Ingresos por hora',
          SalesReportPeriod.week => 'Ingresos por día',
          SalesReportPeriod.month => 'Ingresos por semana',
        }, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          _periodDescription(report),
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (report.unitsSold == 0)
          const SizedBox(
            height: 150,
            child: Center(
              child: Text(
                'Sin ingresos en este periodo',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
        else
          SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                minY: 0,
                alignment: BarChartAlignment.spaceBetween,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.black.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) => Text(
                        _formatCompactCurrency(value),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= report.buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          report.buckets[index].label,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < report.buckets.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: report.buckets[index].revenue,
                          color: Colors.indigo,
                          width: 17,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final bucket = report.buckets[group.x];
                      return BarTooltipItem(
                        '${bucket.label}\n${_formatCurrency(bucket.revenue)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatCompactCurrency(double amount) {
    if (amount >= 1000000) {
      return '₡${(amount / 1000000).toStringAsFixed(2)} M';
    }
    if (amount >= 1000) {
      return '₡${(amount / 1000).toStringAsFixed(2)} mil';
    }
    return '₡${amount.toStringAsFixed(2)}';
  }

  Widget _buildTopProducts(SalesReportData report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Productos más vendidos',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (report.topProducts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Sin ventas en este periodo',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else
          for (var index = 0; index < report.topProducts.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.indigo.shade50,
                foregroundColor: Colors.indigo,
                child: Text('${index + 1}'),
              ),
              title: Text(
                report.topProducts[index].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${report.topProducts[index].unitsSold} unidades'),
              trailing: Text(
                _formatCurrency(report.topProducts[index].revenue),
                style: const TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildSaleItem(Map<String, dynamic> sale) {
    final rawDate = sale['date'];
    final date = rawDate is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(rawDate.toDate())
        : rawDate?.toString() ?? '';
    return Dismissible(
      key: Key(sale['firestoreId'].toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _eliminarVenta(sale),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          child: Icon(Icons.receipt),
        ),
        title: Text(
          (sale['productName'] ?? sale['product_name'])?.toString() ??
              'Producto sin nombre',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Fecha: $date'),
        trailing: Text(
          _formatCurrency((sale['price'] as num?) ?? 0),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final filteredSales = _filteredSales;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes y ventas'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar reportes',
            onPressed: _loading ? null : _cargarVentas,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Borrar historial',
            onPressed: _confirmarBorrarHistorial,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text('No se pudieron cargar las ventas: $_loadError'))
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: SegmentedButton<SalesReportPeriod>(
                      segments: const [
                        ButtonSegment(
                          value: SalesReportPeriod.day,
                          label: Text('Día'),
                          icon: Icon(Icons.today),
                        ),
                        ButtonSegment(
                          value: SalesReportPeriod.week,
                          label: Text('Semana'),
                          icon: Icon(Icons.date_range),
                        ),
                        ButtonSegment(
                          value: SalesReportPeriod.month,
                          label: Text('Mes'),
                          icon: Icon(Icons.calendar_month),
                        ),
                      ],
                      selected: {_period},
                      onSelectionChanged: (selection) {
                        _selectPeriod(selection.first);
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        _buildMetric(
                          label: 'Ingresos · ${_periodDescription(report)}',
                          value: _formatCurrency(report.totalIncome),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        const SizedBox(width: 10),
                        _buildMetric(
                          label: 'Unidades vendidas',
                          value: '${report.unitsSold}',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildRevenueChart(report)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildTopProducts(report)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto en el historial',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Historial completo de ventas',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (filteredSales.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('No hay ventas para este periodo o búsqueda'),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: filteredSales.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSaleItem(filteredSales[index]),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}
