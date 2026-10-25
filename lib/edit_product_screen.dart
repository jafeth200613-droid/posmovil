import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'scanner_screen.dart';

class EditProductScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;

  String _categoriaSeleccionada = 'General';
  final List<String> _categorias = [
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
    'Verduras y Frutas'
  ];

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.product['code']);
    _nameController = TextEditingController(text: widget.product['name']);
    _priceController = TextEditingController(text: widget.product['price'].toString());
    _stockController = TextEditingController(text: widget.product['stock'].toString());
    
    String catActual = widget.product['category'] ?? 'General';
    if (_categorias.contains(catActual)) {
      _categoriaSeleccionada = catActual;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _escanearCodigo() async {
    final codigo = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );
    if (codigo != null && codigo is String) {
      setState(() {
        _codeController.text = codigo;
      });
    }
  }

  void _actualizarProducto() async {
    if (_formKey.currentState!.validate()) {
      String codigoFinal = _codeController.text.trim();
      if (codigoFinal.isEmpty) {
        codigoFinal = 'VERD-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      }

      final productoActualizado = {
        'id': widget.product['id'],
        'code': codigoFinal,
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'stock': int.parse(_stockController.text.trim()),
        'category': _categoriaSeleccionada,
      };

      await DatabaseHelper.instance.updateProduct(productoActualizado);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Producto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Código de Barras / SKU (Opcional)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.indigo),
                    onPressed: _escanearCodigo,
                    tooltip: 'Escanear código',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre del Producto', border: OutlineInputBorder()),
                validator: (value) => value == null || value.isEmpty ? 'Ingrese un nombre' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _categoriaSeleccionada,
                decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
                items: _categorias.map((cat) {
                  return DropdownMenuItem(value: cat, child: Text(cat));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _categoriaSeleccionada = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Precio (₡)', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || double.tryParse(value) == null) return 'Ingrese un precio válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stock', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || int.tryParse(value) == null) return 'Ingrese un stock válido';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _actualizarProducto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Actualizar Producto', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}