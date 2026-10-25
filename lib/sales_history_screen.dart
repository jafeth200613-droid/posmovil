import 'package:flutter/material.dart';
import 'database_helper.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  double _totalHoy = 0.0;
  int _cantidadVentasHoy = 0;

  @override
  void initState() {
    super.initState();
    _cargarVentas();
  }

  Future<void> _cargarVentas() async {
    final sales = await DatabaseHelper.instance.getSales();
    
    // Obtener la fecha actual en formato YYYY-MM-DD para calcular el corte de hoy
    final hoyStr = DateTime.now().toString().substring(0, 10);
    
    double totalTemp = 0.0;
    int countTemp = 0;

    for (var sale in sales) {
      final fechaVenta = sale['date'].toString();
      if (fechaVenta.startsWith(hoyStr)) {
        totalTemp += (sale['price'] as num).toDouble();
        countTemp++;
      }
    }

    setState(() {
      _sales = sales;
      _totalHoy = totalTemp;
      _cantidadVentasHoy = countTemp;
    });
  }

  void _confirmarBorrarHistorial() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar historial?'),
        content: const Text('Esta acción eliminará todos los registros de ventas. ¿Deseas continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseHelper.instance.deleteAllSales();
              Navigator.pop(context);
              _cargarVentas();
            },
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial y Corte de Caja'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Borrar historial',
            onPressed: _confirmarBorrarHistorial,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tarjeta de Corte de Caja Diario
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.indigo.shade200, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.point_of_sale, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(
                      'Corte de Caja Diario (Hoy)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ventas realizadas:', style: TextStyle(fontSize: 16)),
                    Text('$_cantidadVentasHoy', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total recaudado:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      '₡$_totalHoy',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Todas las transacciones (Desliza para eliminar)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: _sales.isEmpty
                ? const Center(
                    child: Text(
                      'No hay ventas registradas',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _sales.length,
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      return Dismissible(
                        key: Key(sale['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) async {
                          await DatabaseHelper.instance.deleteSale(sale['id']);
                          _cargarVentas();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Venta eliminada del historial')),
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              child: Icon(Icons.receipt),
                            ),
                            title: Text(
                              sale['product_name'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('Fecha: ${sale['date']}'),
                            trailing: Text(
                              '₡${sale['price']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}