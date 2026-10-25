import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'scanner_screen.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();

  String _categoriaSeleccionada = 'General';
  String _unidadMedida = 'Unidades / Kilos';

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

  final List<String> _opcionesPeso = [
    '100 g',
    '250 g',
    '500 g (1/2 kg)',
    '1 kg',
    '2 kg',
    '5 kg',
    '10 kg',
    '20 kg',
    'Personalizado'
  ];

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

  void _guardarProducto() async {
    if (_formKey.currentState!.validate()) {
      // Si el código está vacío, generamos uno automáticamente con la fecha/hora
      String codigoFinal = _codeController.text.trim();
      if (codigoFinal.isEmpty) {
        codigoFinal = 'VERD-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      }

      final nuevoProducto = {
        'code': codigoFinal,
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'stock': int.parse(_stockController.text.trim()),
        'category': _categoriaSeleccionada,
      };

      await DatabaseHelper.instance.insertProduct(nuevoProducto);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esVerduraOFruta = _categoriaSeleccionada == 'Verduras y Frutas';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar Producto'),
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
                  helperText: 'Si lo dejas vacío, se asignará un código automático',
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
                decoration: const InputDecoration(
                  labelText: 'Nombre del Producto',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Ingrese un nombre' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _categoriaSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
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
              if (esVerduraOFruta) ...[
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Peso de Entrada / Empaque rápido',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.scale, color: Colors.green),
                  ),
                  hint: const Text('Seleccionar peso preset'),
                  items: _opcionesPeso.map((peso) {
                    return DropdownMenuItem(value: peso, child: Text(peso));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null && value != 'Personalizado') {
                      int valorNumerico = 1;
                      if (value.contains('100 g')) valorNumerico = 1;
                      if (value.contains('250 g')) valorNumerico = 1;
                      if (value.contains('500 g')) valorNumerico = 1;
                      if (value.contains('1 kg')) valorNumerico = 1;
                      if (value.contains('2 kg')) valorNumerico = 2;
                      if (value.contains('5 kg')) valorNumerico = 5;
                      if (value.contains('10 kg')) valorNumerico = 10;
                      if (value.contains('20 kg')) valorNumerico = 20;

                      _stockController.text = valorNumerico.toString();
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: esVerduraOFruta ? 'Precio (₡) por Unidad / Peso' : 'Precio (₡)',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || double.tryParse(value) == null) return 'Ingrese un precio válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: esVerduraOFruta ? 'Stock Inicial (Unidades / Kilos)' : 'Stock Inicial',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || int.tryParse(value) == null) return 'Ingrese un stock válido';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _guardarProducto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Guardar Producto', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}