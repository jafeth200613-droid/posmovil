import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'sales_ticket_format.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SavedThermalPrinter {
  const SavedThermalPrinter({
    required this.name,
    required this.macAddress,
    this.paperWidth = 58,
  });

  final String name;
  final String macAddress;
  final int paperWidth;

  SavedThermalPrinter copyWith({int? paperWidth}) {
    return SavedThermalPrinter(
      name: name,
      macAddress: macAddress,
      paperWidth: paperWidth ?? this.paperWidth,
    );
  }

  factory SavedThermalPrinter.fromJson(Map<String, dynamic> json) {
    return SavedThermalPrinter(
      name: json['name'] as String,
      macAddress: json['macAddress'] as String,
      paperWidth: json['paperWidth'] as int? ?? 58,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'macAddress': macAddress,
    'paperWidth': paperWidth,
  };
}

class ThermalPrinterService {
  static const _printersKey = 'thermal_printers';
  static const _defaultPrinterKey = 'thermal_default_printer';

  static Future<List<SavedThermalPrinter>> getSavedPrinters() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences
            .getStringList(_printersKey)
            ?.map(
              (value) => SavedThermalPrinter.fromJson(
                jsonDecode(value) as Map<String, dynamic>,
              ),
            )
            .toList() ??
        [];
  }

  static Future<String?> getDefaultPrinterAddress() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_defaultPrinterKey);
  }

  static Future<void> savePrinter(SavedThermalPrinter printer) async {
    final preferences = await SharedPreferences.getInstance();
    final printers = await getSavedPrinters();
    final hasDefaultPrinter = preferences.getString(_defaultPrinterKey) != null;
    final index = printers.indexWhere(
      (saved) => saved.macAddress == printer.macAddress,
    );
    if (index == -1) {
      printers.add(printer);
    } else {
      printers[index] = printer;
    }
    await preferences.setStringList(
      _printersKey,
      printers.map((saved) => jsonEncode(saved.toJson())).toList(),
    );
    if (!hasDefaultPrinter) {
      await preferences.setString(_defaultPrinterKey, printer.macAddress);
    }
  }

  static Future<void> setDefaultPrinter(String macAddress) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_defaultPrinterKey, macAddress);
  }

  static Future<void> updatePaperWidth(
    SavedThermalPrinter printer,
    int paperWidth,
  ) async {
    await savePrinter(printer.copyWith(paperWidth: paperWidth));
  }

  static Future<void> removePrinter(String macAddress) async {
    final preferences = await SharedPreferences.getInstance();
    final printers = await getSavedPrinters();
    printers.removeWhere((printer) => printer.macAddress == macAddress);
    await preferences.setStringList(
      _printersKey,
      printers.map((printer) => jsonEncode(printer.toJson())).toList(),
    );
    if (await getDefaultPrinterAddress() == macAddress) {
      if (printers.isEmpty) {
        await preferences.remove(_defaultPrinterKey);
      } else {
        await preferences.setString(
          _defaultPrinterKey,
          printers.first.macAddress,
        );
      }
    }
  }

  static Future<void> printReceipt({
    required SavedThermalPrinter printer,
    required List<Map<String, dynamic>> items,
    required double total,
    required DateTime date,
  }) async {
    final profile = await CapabilityProfile.load();
    final paperSize = printer.paperWidth == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    final ticketLines = formatSalesTicketLines(
      items: items,
      total: total,
      date: date,
    );
    final bytes = <int>[...generator.reset()];

    for (var index = 0; index < ticketLines.length; index++) {
      final line = formatTicketLineForPrinter(ticketLines[index]);
      final isTitle = index == 0;
      final isDate = index == 1;
      final isTotal = index == ticketLines.length - 2;
      final isThanks = index == ticketLines.length - 1;
      bytes.addAll(
        generator.text(
          line,
          styles: PosStyles(
            align: isTitle || isDate || isThanks
                ? PosAlign.center
                : isTotal
                ? PosAlign.right
                : PosAlign.left,
            bold: isTitle || isTotal,
            width: isTitle || isTotal ? PosTextSize.size2 : PosTextSize.size1,
            height: isTitle || isTotal ? PosTextSize.size2 : PosTextSize.size1,
          ),
        ),
      );
    }

    bytes.addAll(generator.feed(3));

    await _sendToPrinter(printer, bytes);
  }

  static Future<void> printTest(SavedThermalPrinter printer) async {
    final profile = await CapabilityProfile.load();
    final paperSize = printer.paperWidth == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final generator = Generator(paperSize, profile);
    final bytes = <int>[
      ...generator.reset(),
      ...generator.text(
        'PRUEBA DE IMPRESION',
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1,
      ),
      ...generator.text(
        printer.name,
        styles: const PosStyles(align: PosAlign.center),
      ),
      ...generator.text(
        printer.macAddress,
        styles: const PosStyles(align: PosAlign.center),
      ),
      ...generator.feed(3),
    ];
    await _sendToPrinter(printer, bytes);
  }

  static Future<void> _sendToPrinter(
    SavedThermalPrinter printer,
    List<int> bytes,
  ) async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw StateError('No se concedió el permiso de Bluetooth.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw StateError('Activa Bluetooth en el teléfono.');
    }

    final connected = await PrintBluetoothThermal.connect(
      macPrinterAddress: printer.macAddress,
    );
    if (!connected) {
      throw StateError('No se pudo conectar con ${printer.name}.');
    }

    try {
      final printed = await PrintBluetoothThermal.writeBytes(bytes);
      if (!printed) {
        throw StateError('La impresora no confirmó la recepción del ticket.');
      }
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }
}
