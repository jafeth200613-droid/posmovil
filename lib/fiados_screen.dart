import 'dart:async';

import 'package:flutter/material.dart';

import 'currency_format.dart';
import 'database_helper.dart';
import 'subscription_service.dart';

class FiadosScreen extends StatefulWidget {
  const FiadosScreen({super.key});

  @override
  State<FiadosScreen> createState() => _FiadosScreenState();
}

class _FiadosScreenState extends State<FiadosScreen> {
  List<Map<String, dynamic>> _fiados = [];

  @override
  void initState() {
    super.initState();
    _cargarFiados();
  }

  Future<void> _cargarFiados() async {
    final data = await DatabaseHelper.instance.getFiados();
    if (!mounted) return;
    setState(() {
      _fiados = data;
    });
  }

  Future<void> _mostrarDialogoNuevoFiado() async {
    Map<String, Object>? fiado;
    fiado = await showDialog<Map<String, Object>>(
      context: context,
      builder: (dialogContext) {
        var clientName = '';
        var rawAmount = '';
        return AlertDialog(
          title: const Text('Nuevo Fiado / Cuenta por Cobrar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => clientName = value,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Cliente',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (value) => rawAmount = value,
                decoration: const InputDecoration(
                  labelText: 'Monto Deuda (₡)',
                  helperText: 'Escribe un monto mayor que cero',
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
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final normalizedName = clientName.trim();
                final amount = double.tryParse(
                  rawAmount.trim().replaceAll(',', '.'),
                );

                if (normalizedName.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Escribe el nombre del cliente.'),
                    ),
                  );
                  return;
                }
                if (amount == null || !amount.isFinite || amount <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Escribe un monto válido mayor que cero.'),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, {
                  'clientName': normalizedName,
                  'amount': amount,
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (fiado == null) return;

    try {
      final selectedItems = await _seleccionarProductos();
      if (selectedItems == null || !mounted) return;
      await DatabaseHelper.instance.insertFiado(
        clientName: fiado['clientName']! as String,
        amount: fiado['amount']! as double,
        date: DateTime.now().toString().substring(0, 16),
        items: selectedItems,
      );
      await _cargarFiados();
    } catch (error) {
      debugPrint('No se pudo guardar el fiado: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la cuenta: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>?> _seleccionarProductos() async {
    final products = await DatabaseHelper.instance.getProducts();
    if (!mounted) return null;
    if (products.isEmpty) return [];

    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _FiadoProductSelectionDialog(products: products),
    );
  }

  Future<void> _agregarProducto(Map<String, dynamic> fiado) async {
    final products = await DatabaseHelper.instance.getProducts();
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero agrega productos al inventario.'),
        ),
      );
      return;
    }

    final selection = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _FiadoAddProductDialog(products: products),
    );
    if (selection == null) return;

    try {
      await DatabaseHelper.instance.addFiadoItem(
        fiadoId: fiado['id'] as int,
        productId: selection['id'] as int,
        productName: selection['name'] as String,
        unitPrice: (selection['price'] as num).toDouble(),
        quantity: selection['quantity'] as int,
      );
      await _cargarFiados();
    } catch (error) {
      debugPrint('No se pudo agregar el producto al fiado: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo agregar el producto: $error')),
      );
    }
  }

  Future<void> _setFiadoItemPaid({
    required Map<String, dynamic> fiado,
    required Map<String, dynamic> item,
    required bool paid,
  }) async {
    final itemId = item['id'] as int;
    await DatabaseHelper.instance.setFiadoItemPaid(itemId, paid: paid);

    unawaited(_syncFiadoSales(fiado: fiado, items: [item], paid: paid));
  }

  Future<void> _setFiadoPaid({
    required Map<String, dynamic> fiado,
    required bool paid,
  }) async {
    final fiadoId = fiado['id'] as int;
    final database = DatabaseHelper.instance;
    final itemsBefore = await database.getFiadoItems(fiadoId);
    final changedItemsBefore = itemsBefore
        .where((item) => (item['status'] == 'paid') != paid)
        .toList();

    await database.setFiadoPaid(fiadoId, paid: paid);
    var changedItems = changedItemsBefore;
    if (paid && itemsBefore.isEmpty) {
      changedItems = (await database.getFiadoItems(fiadoId))
          .where((item) => item['status'] == 'paid')
          .toList();
    }
    if (changedItems.isEmpty) return;

    unawaited(_syncFiadoSales(fiado: fiado, items: changedItems, paid: paid));
  }

  Future<void> _syncFiadoSales({
    required Map<String, dynamic> fiado,
    required List<Map<String, dynamic>> items,
    required bool paid,
  }) async {
    try {
      if (paid) {
        await SubscriptionService.recordFiadoSales(
          fiadoId: fiado['id'] as int,
          clientName: fiado['client_name'].toString(),
          items: items,
        );
      } else {
        await SubscriptionService.deleteFiadoSales(
          fiadoId: fiado['id'] as int,
          items: items,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo sincronizar el historial del fiado: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El cambio quedó guardado en este dispositivo, pero no se pudo '
            'sincronizar el historial: $error',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _mostrarDetalleFiado(Map<String, dynamic> initialFiado) async {
    var fiado = Map<String, dynamic>.from(initialFiado);
    var items = await DatabaseHelper.instance.getFiadoItems(fiado['id'] as int);
    final updatingItemIds = <int>{};
    var updatingFiado = false;
    var editandoNombre = false;
    var nombreEditado = fiado['client_name'].toString();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refresh() async {
            final freshItems = await DatabaseHelper.instance.getFiadoItems(
              fiado['id'] as int,
            );
            final freshAccounts = await DatabaseHelper.instance.getFiados();
            final freshFiado = freshAccounts.firstWhere(
              (account) => account['id'] == fiado['id'],
              orElse: () => fiado,
            );
            if (!dialogContext.mounted) return;
            setDialogState(() {
              items = freshItems;
              fiado = Map<String, dynamic>.from(freshFiado);
            });
            await _cargarFiados();
          }

          final isPaid = fiado['status'] == 'paid';
          return AlertDialog(
            title: editandoNombre
                ? TextField(
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) => nombreEditado = value,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del cliente',
                    ),
                  )
                : Text(fiado['client_name'].toString()),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Saldo pendiente: ₡${formatMoney(fiado['amount'] as num)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Esta cuenta aún no tiene productos.'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final itemPaid = item['status'] == 'paid';
                          final itemId = item['id'] as int;
                          final isUpdating =
                              updatingFiado || updatingItemIds.isNotEmpty;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item['product_name'].toString()),
                            subtitle: Text(
                              '${item['quantity']} x ₡${formatMoney(item['unit_price'] as num)}'
                              ' · ${itemPaid ? 'Pagado' : 'Pendiente'}',
                            ),
                            trailing: TextButton(
                              onPressed: isUpdating
                                  ? null
                                  : () async {
                                      setDialogState(
                                        () => updatingItemIds.add(itemId),
                                      );
                                      try {
                                        await _setFiadoItemPaid(
                                          fiado: fiado,
                                          item: item,
                                          paid: !itemPaid,
                                        );
                                        await refresh();
                                      } catch (error) {
                                        debugPrint(
                                          'No se pudo actualizar producto fiado: $error',
                                        );
                                        if (!dialogContext.mounted) return;
                                        ScaffoldMessenger.of(
                                          dialogContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'No se pudo actualizar: $error',
                                            ),
                                          ),
                                        );
                                      } finally {
                                        if (dialogContext.mounted) {
                                          setDialogState(
                                            () =>
                                                updatingItemIds.remove(itemId),
                                          );
                                        }
                                      }
                                    },
                              child: updatingItemIds.contains(itemId)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(itemPaid ? 'Reanudar' : 'Pagado'),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  if (!editandoNombre) {
                    setDialogState(() {
                      editandoNombre = true;
                      nombreEditado = fiado['client_name'].toString();
                    });
                    return;
                  }
                  final value = nombreEditado.trim();
                  if (value.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Escribe un nombre.')),
                    );
                    return;
                  }
                  try {
                    await DatabaseHelper.instance.updateFiadoName(
                      fiado['id'] as int,
                      value,
                    );
                    setDialogState(() => editandoNombre = false);
                    await refresh();
                  } catch (error) {
                    debugPrint(
                      'No se pudo editar el cliente del fiado: $error',
                    );
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('No se pudo editar: $error')),
                    );
                  }
                },
                icon: Icon(editandoNombre ? Icons.save : Icons.edit),
                label: Text(editandoNombre ? 'Guardar nombre' : 'Editar'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _agregarProducto(fiado);
                  await refresh();
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Agregar producto'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                onPressed: updatingFiado || updatingItemIds.isNotEmpty
                    ? null
                    : () async {
                        setDialogState(() => updatingFiado = true);
                        try {
                          await _setFiadoPaid(fiado: fiado, paid: !isPaid);
                          await refresh();
                        } catch (error) {
                          debugPrint(
                            'No se pudo cambiar el estado del fiado: $error',
                          );
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text('No se pudo actualizar: $error'),
                            ),
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => updatingFiado = false);
                          }
                        }
                      },
                child: updatingFiado
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isPaid ? 'Reanudar cuenta' : 'Marcar pagada'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _registrarAbono(Map<String, dynamic> fiado) {
    final abonoController = TextEditingController();
    var isApplyingAbono = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Registrar Abono: ${fiado['client_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deuda actual: ₡${formatMoney(fiado['amount'] as num)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: abonoController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Monto del Abono (₡)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isApplyingAbono
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: isApplyingAbono
                  ? null
                  : () async {
                      final abono = double.tryParse(abonoController.text);
                      if (abono == null || !abono.isFinite || abono <= 0) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Escribe un monto válido.'),
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isApplyingAbono = true);
                      try {
                        final deudaActual = (fiado['amount'] as num).toDouble();
                        final nuevaDeuda = double.parse(
                          (deudaActual - abono).toStringAsFixed(2),
                        );
                        if (nuevaDeuda <= 0) {
                          await _setFiadoPaid(fiado: fiado, paid: true);
                        } else {
                          await DatabaseHelper.instance.updateFiado({
                            'id': fiado['id'],
                            'client_name': fiado['client_name'],
                            'amount': nuevaDeuda,
                            'date': fiado['date'],
                          });
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _cargarFiados();
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              nuevaDeuda <= 0
                                  ? 'La cuenta quedó pagada; la venta aparecerá en '
                                        'Reportes al sincronizar.'
                                  : 'Abono registrado. Nuevo saldo: '
                                        '₡${formatMoney(nuevaDeuda)}',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (error) {
                        debugPrint('No se pudo registrar el abono: $error');
                        if (!mounted) return;
                        if (dialogContext.mounted) {
                          setDialogState(() => isApplyingAbono = false);
                        }
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'No se pudo registrar el abono: $error',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: isApplyingAbono
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aplicar Abono'),
            ),
          ],
        ),
      ),
    ).then((_) => abonoController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    double totalFiados = _fiados.fold(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Fiados'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade200, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.book_online, color: Colors.orange, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Total por Cobrar:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '₡${formatMoney(totalFiados)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Clientes con cuentas pendientes (Desliza para borrar)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _fiados.isEmpty
                ? const Center(
                    child: Text(
                      'No hay cuentas fiadas registradas',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _fiados.length,
                    itemBuilder: (context, index) {
                      final fiado = _fiados[index];
                      return Dismissible(
                        key: Key(fiado['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) async {
                          await DatabaseHelper.instance.deleteFiado(
                            fiado['id'],
                          );
                          if (!context.mounted) return;
                          _cargarFiados();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Registro de fiado eliminado'),
                            ),
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: ListTile(
                            onTap: () => _mostrarDetalleFiado(fiado),
                            leading: const CircleAvatar(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              child: Icon(Icons.person),
                            ),
                            title: Text(
                              fiado['client_name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              'Fecha: ${fiado['date']} · '
                              '${fiado['status'] == 'paid' ? 'Pagado' : 'Pendiente'} '
                              '· Toca para editar productos',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₡${formatMoney(fiado['amount'] as num)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _registrarAbono(fiado),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  child: const Text('Abonar'),
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
        onPressed: _mostrarDialogoNuevoFiado,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo Fiado'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _FiadoProductSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;

  const _FiadoProductSelectionDialog({required this.products});

  @override
  State<_FiadoProductSelectionDialog> createState() =>
      _FiadoProductSelectionDialogState();
}

class _FiadoProductSelectionDialogState
    extends State<_FiadoProductSelectionDialog> {
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vincular productos (opcional)'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.products.isEmpty
            ? const Text('No hay productos en el inventario.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.products.length,
                itemBuilder: (context, index) {
                  final product = widget.products[index];
                  final id = product['id'] as int;
                  return CheckboxListTile(
                    value: _selectedIds.contains(id),
                    title: Text(product['name'].toString()),
                    subtitle: Text(
                      '₡${formatMoney(product['price'] as num)} · Stock ${product['stock']}',
                    ),
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final selected = widget.products
                .where((product) => _selectedIds.contains(product['id']))
                .map(
                  (product) => <String, dynamic>{
                    'id': product['id'],
                    'name': product['name'],
                    'price': product['price'],
                    'quantity': 1,
                  },
                )
                .toList();
            Navigator.pop(context, selected);
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _FiadoAddProductDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;

  const _FiadoAddProductDialog({required this.products});

  @override
  State<_FiadoAddProductDialog> createState() => _FiadoAddProductDialogState();
}

class _FiadoAddProductDialogState extends State<_FiadoAddProductDialog> {
  late int _selectedProductId = widget.products.first['id'] as int;
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final selectedProductId =
        widget.products.any((product) => product['id'] == _selectedProductId)
        ? _selectedProductId
        : widget.products.first['id'] as int;
    final selectedProduct = widget.products.firstWhere(
      (product) => product['id'] == selectedProductId,
      orElse: () => widget.products.first,
    );

    return AlertDialog(
      title: const Text('Agregar producto al fiado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey(selectedProductId),
            initialValue: selectedProductId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Producto',
              border: OutlineInputBorder(),
            ),
            items: widget.products
                .map(
                  (product) => DropdownMenuItem(
                    value: product['id'] as int,
                    child: Text(
                      '${product['name']} · ₡${formatMoney(product['price'] as num)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (product) {
              if (product != null) {
                setState(() => _selectedProductId = product);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cantidad'),
              Row(
                children: [
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_quantity'),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Total: ₡${formatMoney((selectedProduct['price'] as num) * _quantity)}',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'id': selectedProduct['id'],
            'name': selectedProduct['name'].toString(),
            'price': selectedProduct['price'],
            'quantity': _quantity,
          }),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
