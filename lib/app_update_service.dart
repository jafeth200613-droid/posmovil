import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AvailableAppUpdate {
  const AvailableAppUpdate({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotes,
  });

  final String version;
  final int buildNumber;
  final Uri apkUrl;
  final String sha256;
  final String releaseNotes;

  factory AvailableAppUpdate.fromJson(Map<String, dynamic> json) {
    if (json['packageName'] != 'com.jafeth.posmovil') {
      throw const FormatException('El paquete de la actualización no coincide.');
    }

    final version = json['version'];
    final buildNumber = json['buildNumber'];
    final apkUrl = Uri.tryParse(json['apkUrl']?.toString() ?? '');
    final checksum = json['sha256']?.toString().toLowerCase() ?? '';
    final releaseNotes = json['releaseNotes']?.toString() ?? '';

    if (version is! String ||
        buildNumber is! int ||
        apkUrl == null ||
        apkUrl.scheme != 'https' ||
        apkUrl.host != 'github.com' ||
        !apkUrl.path.startsWith(
          '/jafeth200613-droid/posmovil/releases/download/',
        ) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('El manifiesto de actualización no es válido.');
    }

    return AvailableAppUpdate(
      version: version,
      buildNumber: buildNumber,
      apkUrl: apkUrl,
      sha256: checksum,
      releaseNotes: releaseNotes,
    );
  }
}

class NoPublishedAppReleaseException implements Exception {
  const NoPublishedAppReleaseException();
}

class AppUpdateService {
  static final Uri _manifestUrl = Uri.parse(
    'https://github.com/jafeth200613-droid/posmovil/releases/latest/download/latest.json',
  );

  Future<AvailableAppUpdate?> checkForUpdate() async {
    if (!Platform.isAndroid || kDebugMode) {
      throw StateError(
        'El actualizador GitHub solo funciona en la versión Android de publicación.',
      );
    }

    final response = await http
        .get(
          _manifestUrl,
          headers: const {'Cache-Control': 'no-cache'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 404) {
      throw const NoPublishedAppReleaseException();
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'GitHub respondió con el estado ${response.statusCode}.',
        uri: _manifestUrl,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('El manifiesto de GitHub no es válido.');
    }
    if (decoded['published'] == false) return null;

    final update = AvailableAppUpdate.fromJson(decoded);
    final packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.packageName != 'com.jafeth.posmovil') {
      throw StateError('El identificador instalado no coincide con POSMOVIL.');
    }

    final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    return update.buildNumber > installedBuild ? update : null;
  }

  Future<void> downloadAndOpen(
    AvailableAppUpdate update, {
    required ValueChanged<double> onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final apkFile = File(
      '${directory.path}${Platform.pathSeparator}posmovil-update-${update.buildNumber}.apk',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 2;

    try {
      final request = await client.getUrl(update.apkUrl).timeout(
        const Duration(seconds: 30),
      );
      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'No se pudo descargar el APK (HTTP ${response.statusCode}).',
          uri: update.apkUrl,
        );
      }
      if (response.contentLength > 300 * 1024 * 1024) {
        throw const FormatException('El APK supera el tamaño permitido.');
      }

      final sink = apkFile.openWrite();
      var receivedBytes = 0;
      try {
        await for (final chunk in response) {
          receivedBytes += chunk.length;
          if (receivedBytes > 300 * 1024 * 1024) {
            throw const FormatException('El APK supera el tamaño permitido.');
          }
          sink.add(chunk);
          if (response.contentLength > 0) {
            onProgress(receivedBytes / response.contentLength);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final actualChecksum = await sha256.bind(apkFile.openRead()).first;
      if (actualChecksum.toString() != update.sha256) {
        throw const FormatException(
          'La verificación de seguridad del APK falló; no se abrirá el instalador.',
        );
      }

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw StateError(
          result.type == ResultType.permissionDenied
              ? 'Permite a POSMOVIL instalar aplicaciones desde esta fuente en los ajustes de Android.'
              : 'Android no pudo abrir el instalador: ${result.message}',
        );
      }
    } catch (_) {
      if (await apkFile.exists()) await apkFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

class AppUpdateButton extends StatefulWidget {
  const AppUpdateButton({super.key});

  @override
  State<AppUpdateButton> createState() => _AppUpdateButtonState();
}

class _AppUpdateButtonState extends State<AppUpdateButton> {
  final AppUpdateService _service = AppUpdateService();
  bool _busy = false;
  double? _progress;

  Future<void> _checkForUpdate() async {
    if (_busy) return;
    if (!Platform.isAndroid || kDebugMode) {
      _showMessage(
        'Las actualizaciones GitHub se habilitan en la versión Android de producción.',
      );
      return;
    }
    setState(() => _busy = true);

    try {
      final update = await _service.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        _showMessage('No hay actualizaciones disponibles.');
        return;
      }

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('POSMOVIL ${update.version} disponible'),
          content: SingleChildScrollView(
            child: Text(
              update.releaseNotes.isEmpty
                  ? 'Hay una nueva versión. Descárgala para continuar.'
                  : update.releaseNotes,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );

      if (shouldInstall != true || !mounted) return;
      setState(() => _progress = 0);
      await _service.downloadAndOpen(
        update,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress.clamp(0, 1));
        },
      );
      if (mounted) {
        _showMessage(
          'Descarga verificada. Revisa el instalador de Android y confirma la actualización.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is NoPublishedAppReleaseException
              ? 'Aún no hay una versión publicada en GitHub.'
              : 'No se pudo actualizar: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _progress == null
          ? 'Buscar actualizaciones'
          : 'Descargando actualización',
      onPressed: _busy ? null : _checkForUpdate,
      icon: _progress == null
          ? const Icon(Icons.system_update_alt)
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: _progress,
                strokeWidth: 2,
              ),
            ),
    );
  }
}