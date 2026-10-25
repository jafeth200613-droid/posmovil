import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

class AppUpdateService {
  StreamSubscription<InstallStatus>? _installSubscription;

  Future<void> checkForFlexibleUpdate({
    required void Function() onUpdateDownloaded,
    required void Function(String message) onError,
  }) async {
    if (!Platform.isAndroid || kDebugMode) return;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress &&
          updateInfo.installStatus == InstallStatus.downloaded) {
        onUpdateDownloaded();
        return;
      }

      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable ||
          !updateInfo.flexibleUpdateAllowed) {
        return;
      }

      await _installSubscription?.cancel();
      _installSubscription = InAppUpdate.installUpdateListener.listen(
        (status) {
          if (status == InstallStatus.downloaded) {
            onUpdateDownloaded();
          } else if (status == InstallStatus.failed) {
            onError('No se pudo descargar la actualización desde Google Play.');
          }
        },
        onError: (Object error) {
          onError('No se pudo revisar la actualización: $error');
        },
      );

      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.inAppUpdateFailed) {
        onError('Google Play no pudo iniciar la actualización.');
      }
    } catch (error) {
      if (error is PlatformException &&
          error.code == 'ERROR_API_NOT_AVAILABLE') {
        return;
      }
      onError('No se pudo revisar la actualización: $error');
    }
  }

  Future<void> completeFlexibleUpdate() async {
    await InAppUpdate.completeFlexibleUpdate();
  }

  Future<void> dispose() async {
    await _installSubscription?.cancel();
  }
}