import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'thermal_printer_service.dart';

class ThermalPrintersScreen extends StatefulWidget {
  const ThermalPrintersScreen({super.key});

  @override
  State<ThermalPrintersScreen> createState() => _ThermalPrintersScreenState();
}

class _ThermalPrintersScreenState extends State<ThermalPrintersScreen> {
  List<SavedThermalPrinter> _printers = [];
  List<BluetoothInfo> _pairedDevices = [];
  String? _defaultPrinterAddress;
  bool _permissionGranted = false;
  bool _bluetoothEnabled = false;
  bool _loading = true;
  String? _loadError;
  String? _printingAddress;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final permissionGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      final printers = await ThermalPrinterService.getSavedPrinters();
      final defaultAddress =
          await ThermalPrinterService.getDefaultPrinterAddress();
      final bluetoothEnabled = permissionGranted
          ? await PrintBluetoothThermal.bluetoothEnabled
          : false;
      final pairedDevices = permissionGranted && bluetoothEnabled
          ? await PrintBluetoothThermal.pairedBluetooths
          : <BluetoothInfo>[];

      if (!mounted) return;
      setState(() {
        _permissionGranted = permissionGranted;
        _bluetoothEnabled = bluetoothEnabled;
        _printers = printers;
        _defaultPrinterAddress = defaultAddress;
        _pairedDevices = pairedDevices;
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

  Future<void> _addPrinter(BluetoothInfo device) async {
    await ThermalPrinterService.savePrinter(
      SavedThermalPrinter(
        name: device.name,
        macAddress: device.macAdress,
      ),
    );
    await _loadPrinters();
  }

  Future<void> _setDefault(SavedThermalPrinter printer) async {
    await ThermalPrinterService.setDefaultPrinter(printer.macAddress);
    await _loadPrinters();
  }

  Future<void> _updatePaperWidth(
    SavedThermalPrinter printer,
    int paperWidth,
  ) async {
    await ThermalPrinterService.updatePaperWidth(printer, paperWidth);
    await _loadPrinters();
  }

  Future<void> _removePrinter(SavedThermalPrinter printer) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar impresora'),
        content: Text('¿Quitar ${printer.name} de las impresoras guardadas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;
    await ThermalPrinterService.removePrinter(printer.macAddress);
    await _loadPrinters();
  }

  Future<void> _printTest(SavedThermalPrinter printer) async {
    setState(() => _printingAddress = printer.macAddress);
    try {
      await ThermalPrinterService.printTest(printer);
      _showMessage('Prueba enviada a ${printer.name}.');
    } catch (error) {
      _showMessage('No se pudo imprimir: $error');
    } finally {
      if (mounted) setState(() => _printingAddress = null);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPairedDevices() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: _pairedDevices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay impresoras emparejadas. Vincula la impresora desde los ajustes Bluetooth del teléfono y vuelve a actualizar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    const ListTile(
                      title: Text(
                        'Dispositivos Bluetooth emparejados',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final device in _pairedDevices)
                      ListTile(
                        leading: const Icon(Icons.print_outlined),
                        title: Text(device.name),
                        subtitle: Text(device.macAdress),
                        trailing: Icon(
                          _printers.any(
                            (printer) =>
                                printer.macAddress == device.macAdress,
                          )
                              ? Icons.check
                              : Icons.add,
                        ),
                        onTap: () async {
                          await _addPrinter(device);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _handlePrinterMenu(
    String action,
    SavedThermalPrinter printer,
  ) async {
    switch (action) {
      case 'test':
        await _printTest(printer);
      case 'paper58':
        await _updatePaperWidth(printer, 58);
      case 'paper80':
        await _updatePaperWidth(printer, 80);
      case 'remove':
        await _removePrinter(printer);
    }
  }

  Widget _buildStatus() {
    final Color color;
    final IconData icon;
    final String message;

    if (!_permissionGranted) {
      color = Colors.orange;
      icon = Icons.lock_outline;
      message = 'Permite el acceso a Bluetooth para buscar impresoras.';
    } else if (!_bluetoothEnabled) {
      color = Colors.orange;
      icon = Icons.bluetooth_disabled;
      message = 'Activa Bluetooth en el teléfono.';
    } else {
      color = Colors.green;
      icon = Icons.bluetooth_connected;
      message = 'Bluetooth activo · ${_pairedDevices.length} dispositivos emparejados';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (!_permissionGranted)
            TextButton(onPressed: _loadPrinters, child: const Text('Permitir')),
        ],
      ),
    );
  }

  Widget _buildPrinterTile(SavedThermalPrinter printer) {
    final isDefault = printer.macAddress == _defaultPrinterAddress;
    final isPrinting = printer.macAddress == _printingAddress;

    return ListTile(
      leading: Icon(
        Icons.print,
        color: isDefault ? Colors.indigo : Colors.black54,
      ),
      title: Text(printer.name),
      subtitle: Text('${printer.macAddress} · ${printer.paperWidth} mm'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: isDefault ? 'Impresora predeterminada' : 'Usar al cobrar',
            onPressed: isDefault ? null : () => _setDefault(printer),
            icon: Icon(
              isDefault ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isDefault ? Colors.indigo : null,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones de impresora',
            onSelected: (action) => _handlePrinterMenu(action, printer),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'test',
                enabled: !isPrinting,
                child: Row(
                  children: [
                    const Icon(Icons.print_outlined),
                    const SizedBox(width: 12),
                    Text(isPrinting ? 'Imprimiendo…' : 'Imprimir prueba'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'paper58', child: Text('Papel 58 mm')),
              const PopupMenuItem(value: 'paper80', child: Text('Papel 80 mm')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'remove', child: Text('Quitar impresora')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresoras térmicas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar dispositivos',
            onPressed: _loading ? null : _loadPrinters,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loading && _loadError == null) _buildStatus(),
          if (_loading) const LinearProgressIndicator(),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No se pudieron cargar las impresoras: $_loadError'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Impresoras guardadas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: !_loading && _permissionGranted && _bluetoothEnabled
                      ? _showPairedDevices
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _printers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aún no hay impresoras guardadas. Empareja una desde Bluetooth y agrégala aquí.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _printers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _buildPrinterTile(_printers[index]),
                  ),
          ),
        ],
      ),
    );
  }
}