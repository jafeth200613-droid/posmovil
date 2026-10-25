import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scanner_error_view.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isScanned = false;
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
          // Si ya escaneó un código, ignoramos cualquier otra lectura inmediata
          if (_isScanned) return;

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;
            if (code != null && code.isNotEmpty) {
              _isScanned = true;
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}