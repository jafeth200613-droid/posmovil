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

## Recuperación de contraseña en Android

Los enlaces de Firebase usan el dominio `posmovil-app.firebaseapp.com` y la ruta
`/__/auth/links` del `AndroidManifest.xml`. Firebase Authentication debe tener
registradas las huellas SHA-1 y SHA-256 de las firmas usadas para instalar la
app. El archivo público `hosting/.well-known/assetlinks.json` debe conservar la
huella SHA-256 de la llave de producción y publicarse en Firebase Hosting con:

```powershell
firebase deploy --only hosting --project posmovil-app
```

Si se cambia la llave de producción, actualiza esa huella en Firebase Console y
en `assetlinks.json`, y vuelve a publicar Hosting. Nunca publiques la keystore
ni sus contraseñas.

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

La primera release publicada es `1.0.1+2`. La versión actual es `1.0.9+10`. El APK se genera en
`build/app/outputs/flutter-apk/app-release.apk`. Antes de instalarlo encima de
la app debug actual, respalda sus datos y desinstálala: la firma de producción
es distinta y Android no permite actualizar entre firmas diferentes.

Las releases `v1.0.1` a `v1.0.7` están publicadas; `v1.0.7` incluye la
recuperación de contraseña mediante enlaces Android, precios con dos decimales,
el precio mensual de ₡800 y el formato neutro del ticket. `v1.0.8` corrige la
apertura y validación de enlaces de recuperación en Android. `v1.0.9` registra
los pagos de fiados en el historial y retira esos registros al reanudar una cuenta.
Para futuras versiones, usa una etiqueta superior, adjunta el APK
con el nombre `POSMOVIL-<versión>.apk` y adjunta también `latest.json`, rellenado con la plantilla
de `release/latest.json.example`, el SHA-256 real del APK y
`"published": true`. En futuras versiones incrementa el número después de `+`
en `pubspec.yaml`, conserva esta misma keystore y vuelve a publicar ambos
assets. El usuario confirma la instalación en el instalador de Android.
