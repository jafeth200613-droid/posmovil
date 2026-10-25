import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerErrorView extends StatelessWidget {
  const ScannerErrorView({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permite el acceso a la cámara en Ajustes > Aplicaciones > POSMOVIL > Permisos.',
      MobileScannerErrorCode.unsupported =>
        'No se encontró una cámara compatible en este dispositivo.',
      MobileScannerErrorCode.controllerInitializing =>
        'La cámara todavía se está iniciando. Intenta de nuevo.',
      _ => error.errorDetails?.message ??
          'No se pudo iniciar la cámara. Comprueba el permiso y vuelve a intentar.',
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Cámara no disponible',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}