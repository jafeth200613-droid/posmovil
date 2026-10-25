import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_inventory_app/scanner_error_view.dart';

void main() {
  testWidgets('camera permission error explains how to recover', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerErrorView(
            error: const MobileScannerException(
              errorCode: MobileScannerErrorCode.permissionDenied,
            ),
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );

    expect(find.text('Cámara no disponible'), findsOneWidget);
    expect(find.textContaining('Ajustes > Aplicaciones > POSMOVIL'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(retryCount, 1);
  });

  testWidgets('unsupported camera error is explained', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerErrorView(
            error: const MobileScannerException(
              errorCode: MobileScannerErrorCode.unsupported,
            ),
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(
      find.text('No se encontró una cámara compatible en este dispositivo.'),
      findsOneWidget,
    );
  });
}
