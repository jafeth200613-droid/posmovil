import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scanner_error_view.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  int _scannerKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Código de Barras'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        key: ValueKey(_scannerKey),
        errorBuilder: (context, error) => ScannerErrorView(
          error: error,
          onRetry: () => setState(() => _scannerKey++),
        ),
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              final String code = barcode.rawValue!;
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}