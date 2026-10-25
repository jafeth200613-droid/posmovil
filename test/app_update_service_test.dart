import 'package:flutter_test/flutter_test.dart';
import 'package:pos_inventory_app/app_update_service.dart';

void main() {
  const validManifest = {
    'packageName': 'com.jafeth.posmovil',
    'version': '1.0.1',
    'buildNumber': 2,
    'apkUrl':
        'https://github.com/jafeth200613-droid/posmovil/releases/download/v1.0.1/POSMOVIL-1.0.1.apk',
    'sha256':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'releaseNotes': 'Mejoras y correcciones.',
  };

  test('accepts a valid manifest from this repository', () {
    final update = AvailableAppUpdate.fromJson(validManifest);

    expect(update.version, '1.0.1');
    expect(update.buildNumber, 2);
    expect(update.apkUrl.host, 'github.com');
    expect(update.sha256, hasLength(64));
  });

  test('rejects a manifest for another package', () {
    expect(
      () => AvailableAppUpdate.fromJson({
        ...validManifest,
        'packageName': 'com.other.app',
      }),
      throwsFormatException,
    );
  });

  test('rejects APK URLs outside this repository release assets', () {
    expect(
      () => AvailableAppUpdate.fromJson({
        ...validManifest,
        'apkUrl': 'https://example.com/posmovil.apk',
      }),
      throwsFormatException,
    );
  });

  test('rejects invalid SHA-256 values', () {
    expect(
      () => AvailableAppUpdate.fromJson({
        ...validManifest,
        'sha256': 'not-a-checksum',
      }),
      throwsFormatException,
    );
  });

  test('rejects APK URLs from another repository', () {
    expect(
      () => AvailableAppUpdate.fromJson({
        ...validManifest,
        'apkUrl':
            'https://github.com/another-owner/another-repo/releases/download/v1.0.1/app.apk',
      }),
      throwsFormatException,
    );
  });
}