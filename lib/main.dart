import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_product_screen.dart';
import 'app_update_service.dart';
import 'database_helper.dart';
import 'edit_product_screen.dart';
import 'fiados_screen.dart';
import 'sales_history_screen.dart';
import 'scanner_screen.dart';
import 'thermal_printer_service.dart';
import 'thermal_printers_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POS e Inventario',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final AppUpdateService _appUpdateService = AppUpdateService();

  final List<Widget> _screens = [
    const InventoryHomeScreen(),
    const PosSalesScreen(),
    const FiadosScreen(),
    const SalesHistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appUpdateService.checkForFlexibleUpdate(
        onUpdateDownloaded: _showUpdateDownloaded,
        onError: _showUpdateError,
      );
    });
  }

  @override
  void dispose() {
    _appUpdateService.dispose();
    super.dispose();
  }

  void _showUpdateDownloaded() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('La actualización está lista para instalar.'),
          action: SnackBarAction(
            label: 'Reiniciar',
            onPressed: () async {
              try {
                await _appUpdateService.completeFlexibleUpdate();
              } catch (error) {
                _showUpdateError('No se pudo instalar la actualización: $error');
              }
            },
          ),
          duration: const Duration(days: 1),
        ),
      );
  }

  void _showUpdateError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Fiados'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reportes'),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// PANTALLA 1: INVENTARIO
// -----------------------------------------------------------------
class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _productosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();

  String _categoriaSeleccionada = 'Todos';
  final List<String> _categoriasFiltro = [
    'Todos',
    'General',
    'Abarrotes',
    'Bebidas',
    'Limpieza',
    'Snacks',
    'Lácteos',
    'Juguetes',
    'Panadería',
    'Electrodomésticos',
    'Uso Personal',
    'Carne',
    'Pastillas',
    'Productos Saludables',
    'Verduras y Frutas',
  ];

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _searchController.addListener(_filtrarProductos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    final data = await DatabaseHelper.instance.getProducts();
    setState(() {
      _productos = data;
      _filtrarProductos();
    });
  }

  void _filtrarProductos() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _productosFiltrados = _productos.where((producto) {
        final nombre = producto['name'].toString().toLowerCase();
        final codigo = producto['code'].toString().toLowerCase();
        final categoria = producto['category'] ?? 'General';

        final cumpleBusqueda = nombre.contains(query) || codigo.contains(query);
        final cumpleCategoria =
            _categoriaSeleccionada == 'Todos' ||
            categoria == _categoriaSeleccionada;

        return cumpleBusqueda && cumpleCategoria;
      }).toList();
    });
  }

  void _irAgregarProducto() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProductScreen()),
    );
    if (resultado == true) _cargarProductos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de Inventario'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por nombre o código',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),
          SizedBox(
            height: 45,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categoriasFiltro.length,
              itemBuilder: (context, index) {
                final cat = _categoriasFiltro[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: _categoriaSeleccionada == cat,
                    onSelected: (selected) {
                      setState(() {
                        _categoriaSeleccionada = cat;
                        _filtrarProductos();
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _productosFiltrados.isEmpty
                ? const Center(
                    child: Text(
                      'No se encontraron productos',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _productosFiltrados.length,
                    itemBuilder: (context, index) {
                      final producto = _productosFiltrados[index];
                      final int stock = producto['stock'];
                      final bool esStockBajo = stock <= 3;

                      return Dismissible(
                        key: Key(producto['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) async {
                          await DatabaseHelper.instance.deleteProduct(
                            producto['id'],
                          );
                          _cargarProductos();
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: ListTile(
                            onTap: () async {
                              final resultado = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      EditProductScreen(product: producto),
                                ),
                              );
                              if (resultado == true) _cargarProductos();
                            },
                            leading: CircleAvatar(
                              backgroundColor: esStockBajo
                                  ? Colors.orange
                                  : Colors.indigo,
                              foregroundColor: Colors.white,
                              child: Icon(
                                esStockBajo
                                    ? Icons.warning_amber_rounded
                                    : Icons.shopping_bag,
                              ),
                            ),
                            title: Text(
                              producto['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Categoría: ${producto['category'] ?? 'General'} | Código: ${producto['code']}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₡${producto['price']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Stock: $stock',
                                  style: TextStyle(
                                    color: esStockBajo
                                        ? Colors.red
                                        : Colors.black87,
                                    fontWeight: esStockBajo
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _irAgregarProducto,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Producto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// -----------------------------------------------------------------
// PANTALLA 2: POS CON CARRITO Y TICKET DE WHATSAPP
// -----------------------------------------------------------------
class PosSalesScreen extends StatefulWidget {
  const PosSalesScreen({super.key});

  @override
  State<PosSalesScreen> createState() => _PosSalesScreenState();
}

class _PosSalesScreenState extends State<PosSalesScreen> {
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _productosFiltrados = [];
  final List<Map<String, dynamic>> _cart = [];
  final TextEditingController _searchController = TextEditingController();

  String _categoriaSeleccionada = 'Todos';
  final List<String> _categoriasFiltro = [
    'Todos',
    'General',
    'Abarrotes',
    'Bebidas',
    'Limpieza',
    'Snacks',
    'Lácteos',
    'Juguetes',
    'Panadería',
    'Electrodomésticos',
    'Uso Personal',
    'Carne',
    'Pastillas',
    'Productos Saludables',
    'Verduras y Frutas',
  ];

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _searchController.addListener(_filtrarProductos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    final data = await DatabaseHelper.instance.getProducts();
    setState(() {
      _productos = data;
      _filtrarProductos();
    });
  }

  void _filtrarProductos() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _productosFiltrados = _productos.where((producto) {
        final nombre = producto['name'].toString().toLowerCase();
        final codigo = producto['code'].toString().toLowerCase();
        final categoria = producto['category'] ?? 'General';
        return (nombre.contains(query) || codigo.contains(query)) &&
            (_categoriaSeleccionada == 'Todos' ||
                categoria == _categoriaSeleccionada);
      }).toList();
    });
  }

  void _agregarAlCarrito(Map<String, dynamic> producto) {
    int stockDisponible = producto['stock'];
    int enCarrito = 0;
    for (var item in _cart) {
      if (item['id'] == producto['id']) {
        enCarrito = item['quantity'];
        break;
      }
    }

    if (enCarrito >= stockDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No hay más stock disponible de este producto'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      final index = _cart.indexWhere((item) => item['id'] == producto['id']);
      if (index >= 0) {
        _cart[index]['quantity'] += 1;
      } else {
        _cart.add({
          'id': producto['id'],
          'name': producto['name'],
          'price': producto['price'],
          'quantity': 1,
          'stock': producto['stock'],
        });
      }
    });
  }

  void _quitarDelCarrito(int index) {
    setState(() {
      if (_cart[index]['quantity'] > 1) {
        _cart[index]['quantity'] -= 1;
      } else {
        _cart.removeAt(index);
      }
    });
  }

  double _calcularTotalCarrito() {
    double total = 0.0;
    for (var item in _cart) {
      total +=
          (item['price'] as num).toDouble() *
          (item['quantity'] as num).toDouble();
    }
    return total;
  }

  void _abrirEscaner() async {
    final codigoEscaneado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (codigoEscaneado != null && codigoEscaneado is String) {
      final productoEncontrado = _productos.firstWhere(
        (p) =>
            p['code'].toString().toLowerCase() == codigoEscaneado.toLowerCase(),
        orElse: () => {},
      );

      if (productoEncontrado.isNotEmpty) {
        _agregarAlCarrito(productoEncontrado);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Producto con código "$codigoEscaneado" no encontrado',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _procesarVenta({bool imprimirTicket = false}) async {
    if (_cart.isEmpty) return;

    final receiptItems = _cart
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final receiptDate = DateTime.now();

    for (var item in _cart) {
      int nuevoStock = item['stock'] - item['quantity'];
      await DatabaseHelper.instance.updateProductStock(item['id'], nuevoStock);

      for (int i = 0; i < item['quantity']; i++) {
        await DatabaseHelper.instance.insertSale({
          'product_name': item['name'],
          'price': item['price'],
          'date': DateTime.now().toString().substring(0, 16),
        });
      }
    }

    String? printError;
    String? printedOn;
    if (imprimirTicket) {
      try {
        final defaultAddress =
            await ThermalPrinterService.getDefaultPrinterAddress();
        if (defaultAddress == null) {
          throw StateError('Configura una impresora predeterminada primero.');
        }

        SavedThermalPrinter? printer;
        for (final savedPrinter
            in await ThermalPrinterService.getSavedPrinters()) {
          if (savedPrinter.macAddress == defaultAddress) {
            printer = savedPrinter;
            break;
          }
        }
        if (printer == null) {
          throw StateError('La impresora predeterminada ya no está guardada.');
        }

        await ThermalPrinterService.printReceipt(
          printer: printer,
          items: receiptItems,
          total: receiptItems.fold<double>(
            0,
            (sum, item) =>
                sum + (item['price'] as num) * (item['quantity'] as num),
          ),
          date: receiptDate,
        );
        printedOn = printer.name;
      } catch (error) {
        printError = error.toString();
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          printError != null
              ? 'Venta guardada, pero no se pudo imprimir: $printError'
              : printedOn != null
              ? 'Venta realizada e impresa en $printedOn.'
              : '✅ ¡Venta realizada con éxito!',
        ),
        backgroundColor: printError == null ? Colors.green : Colors.orange,
      ),
    );

    setState(() {
      _cart.clear();
    });
    _cargarProductos();
  }

  Future<void> _enviarTicketWhatsApp() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('El carrito está vacío')));
      return;
    }

    final total = _calcularTotalCarrito();
    final ticket = StringBuffer()
      ..writeln('🧾 *TICKET DE COMPRA - PULPERÍA* 🏪')
      ..writeln('Fecha: ${DateTime.now().toString().substring(0, 16)}')
      ..writeln('----------------------------------');

    for (final item in _cart) {
      final subtotal =
          (item['price'] as num).toDouble() * (item['quantity'] as num).toInt();
      ticket.writeln('▪️ ${item['name']} x${item['quantity']} - ₡$subtotal');
    }

    ticket
      ..writeln('----------------------------------')
      ..writeln('👉 *TOTAL A PAGAR: ₡$total*')
      ..writeln()
      ..write('¡Gracias por su compra! 🇨🇷');

    final whatsappUrl = Uri.https('wa.me', '/', {'text': ticket.toString()});

    try {
      final launched = await launchUrl(
        whatsappUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched ? 'WhatsApp abrió el mensaje. Revisa y presiona Enviar.' : 'No se pudo abrir WhatsApp. Verifica que tengas un navegador o WhatsApp instalado.',
          ),
          backgroundColor: launched ? Colors.green : Colors.red,
        ),
      );
    } catch (error) {
      debugPrint('No se pudo abrir el ticket en WhatsApp: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp para enviar el ticket.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pasarAFiado() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('El carrito está vacío')));
      return;
    }

    final total = _calcularTotalCarrito();

    final clientName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var clientName = '';
        return AlertDialog(
          title: const Text('Registrar Carrito como Fiado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total a fiar: ₡$total',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => clientName = value,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Cliente',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final value = clientName.trim();
                if (value.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Escribe el nombre del cliente.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Guardar Fiado'),
            ),
          ],
        );
      },
    );

    if (clientName == null || !mounted) return;
    try {
      await DatabaseHelper.instance.insertFiadoFromCart(
        clientName: clientName,
        amount: total,
        date: DateTime.now().toString().substring(0, 16),
        items: List<Map<String, dynamic>>.from(_cart),
      );

      if (!mounted) return;
      setState(_cart.clear);
      await _cargarProductos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cuenta guardada en Fiados.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (error) {
      debugPrint('No se pudo guardar el fiado: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el fiado: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _mostrarCarritoModal() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            double total = _calcularTotalCarrito();
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🧾 Ticket de Venta Actual',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(
                            child: Text(
                              'El carrito está vacío',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  title: Text(
                                    item['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Precio: ₡${item['price']} x ${item['quantity']}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₡${item['price'] * item['quantity']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          setState(
                                            () => _quitarDelCarrito(index),
                                          );
                                          setModalState(() {});
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.green,
                                        ),
                                        onPressed: () {
                                          _agregarAlCarrito(item);
                                          setModalState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total a Pagar:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '₡$total',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _cart.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context, 'cobrar');
                                },
                          icon: const Icon(Icons.check),
                          label: const Text('Cobrar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _cart.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context, 'fiar');
                                },
                          icon: const Icon(Icons.book),
                          label: const Text('Fiar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _cart.isEmpty
                          ? null
                          : () => Navigator.pop(context, 'cobrar_imprimir'),
                      icon: const Icon(Icons.print),
                      label: const Text('Cobrar e imprimir'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _cart.isEmpty ? null : _enviarTicketWhatsApp,
                      icon: const Icon(Icons.share),
                      label: const Text('Enviar Ticket por WhatsApp'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (action == 'fiar') {
      await _pasarAFiado();
    } else if (action == 'cobrar') {
      _procesarVenta();
    } else if (action == 'cobrar_imprimir') {
      _procesarVenta(imprimirTicket: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalItemsCarrito = _cart.fold(
      0,
      (sum, item) => sum + (item['quantity'] as int),
    );
    double totalMontoCarrito = _calcularTotalCarrito();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Punto de Venta (POS)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Impresoras térmicas',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ThermalPrintersScreen(),
                ),
              );
            },
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar por nombre o código',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _abrirEscaner,
                  icon: const Icon(Icons.qr_code_scanner, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  tooltip: 'Escanear código',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 45,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categoriasFiltro.length,
              itemBuilder: (context, index) {
                final cat = _categoriasFiltro[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: _categoriaSeleccionada == cat,
                    onSelected: (selected) {
                      setState(() {
                        _categoriaSeleccionada = cat;
                        _filtrarProductos();
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _productosFiltrados.isEmpty
                ? const Center(
                    child: Text(
                      'No hay productos para vender',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _productosFiltrados.length,
                    itemBuilder: (context, index) {
                      final producto = _productosFiltrados[index];
                      final int stock = producto['stock'];
                      final bool esStockBajo = stock <= 3;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: esStockBajo
                                ? Colors.orange
                                : Colors.green,
                            foregroundColor: Colors.white,
                            child: Icon(
                              esStockBajo
                                  ? Icons.warning_amber_rounded
                                  : Icons.point_of_sale,
                            ),
                          ),
                          title: Text(
                            producto['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Stock disponible: $stock',
                            style: TextStyle(
                              color: esStockBajo ? Colors.red : Colors.black54,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₡${producto['price']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () => _agregarAlCarrito(producto),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Agregar'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.indigo.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalItemsCarrito productos en ticket',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total: ₡$totalMontoCarrito',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _mostrarCarritoModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text('Ver Ticket'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
