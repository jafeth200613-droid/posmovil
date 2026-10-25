# POSMOVIL

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Actualizaciones Android desde GitHub

El botón de actualización consulta la última release pública del repositorio.
Cada release debe incluir el APK y un archivo llamado `latest.json` basado en
`release/latest.json.example`. En el manifiesto, `buildNumber` debe ser mayor al
de la versión instalada, `apkUrl` debe apuntar al APK de esa release y `sha256`
debe ser su hash SHA-256 en minúsculas.

Para calcular el hash en PowerShell:

```powershell
(Get-FileHash .\build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256).Hash.ToLower()
```

Publica ambos archivos como assets de la release de GitHub y nombra el manifiesto
exactamente `latest.json`. Si todavía no hay una release, el botón indicará que
no hay actualizaciones disponibles.

Las versiones deben conservar `com.jafeth.posmovil` y la misma llave de firma.
Android abrirá su instalador y el usuario debe confirmar la instalación; puede
pedir permiso para instalar desde POSMOVIL la primera vez. No publiques APKs
firmados con la llave debug. La app instalada actualmente por depuración debe
reinstalarse una vez con la primera versión firmada de producción.

### Firma y primera release

La keystore `key.jks` y `android/key.properties` son secretos locales y no se
deben subir a GitHub. Crea la configuración local desde la plantilla:

```powershell
Copy-Item android/key.properties.example android/key.properties
```

Abre `android/key.properties` localmente y escribe las contraseñas de la
keystore y de la llave `key`. No compartas ese archivo ni las contraseñas. La
ruta `../key.jks` corresponde a la llave que está en la raíz del proyecto.
Después genera el APK firmado:

```powershell
flutter build apk --release
```

La versión inicial preparada es `1.0.1+2`. El APK se genera en
`build/app/outputs/flutter-apk/app-release.apk`. Antes de instalarlo encima de
la app debug actual, respalda sus datos y desinstálala: la firma de producción
es distinta y Android no permite actualizar entre firmas diferentes.

Para la primera release pública, usa la etiqueta `v1.0.1`, adjunta el APK como
`POSMOVIL-1.0.1.apk` y adjunta también `latest.json`, rellenado con la plantilla
de `release/latest.json.example`, el SHA-256 real del APK y
`"published": true`. En futuras versiones incrementa el número después de `+`
en `pubspec.yaml`, conserva esta misma keystore y vuelve a publicar ambos
assets. El usuario confirma la instalación en el instalador de Android.
