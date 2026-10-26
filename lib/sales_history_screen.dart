import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'database_helper.dart';
import 'sales_report_data.dart';

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

  static final _currencyFormat = NumberFormat.currency(
    locale: 'es_CR',
    symbol: '₡',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _cargarVentas();
  }

  Future<void> _cargarVentas() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final sales = await DatabaseHelper.instance.getSales();
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
  );

  String _formatCurrency(num amount) => _currencyFormat.format(amount);

  String _periodDescription(SalesReportData report) {
    if (_period == SalesReportPeriod.day) return 'Hoy';
    if (_period == SalesReportPeriod.week) {
      return 'Semana del ${report.start.day}/${report.start.month} al '
          '${report.end.subtract(const Duration(days: 1)).day}/${report.end.month}';
    }

    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${months[report.start.month - 1]} ${report.start.year}';
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
    final id = sale['id'] as int;
    await DatabaseHelper.instance.deleteSale(id);
    if (!mounted) return;
    setState(() => _sales.removeWhere((item) => item['id'] == id));
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
        Text(
          switch (_period) {
            SalesReportPeriod.day => 'Ingresos por hora',
            SalesReportPeriod.week => 'Ingresos por día',
            SalesReportPeriod.month => 'Ingresos por semana',
          },
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
    if (amount >= 1000000) return '₡${(amount / 1000000).toStringAsFixed(1)} M';
    if (amount >= 1000) return '₡${(amount / 1000).toStringAsFixed(1)} mil';
    return '₡${amount.round()}';
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
    return Dismissible(
      key: Key(sale['id'].toString()),
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
          sale['product_name']?.toString() ?? 'Producto sin nombre',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Fecha: ${sale['date']}'),
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
                        setState(() => _period = selection.first);
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
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
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
                if (_sales.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No hay ventas registradas')),
                  )
                else
                  SliverList.builder(
                    itemCount: _sales.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSaleItem(_sales[index]),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}