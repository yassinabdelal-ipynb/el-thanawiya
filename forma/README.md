# Flutter application

The El-Thanawiya Android app runs one frozen neural network locally. No Python process, network service, or account is required on the phone. The internal package name `forma` and Android ID `com.ahmed.forma` are retained for compatibility.

## Toolchain

The source has been built with Flutter 3.47.6 / Dart 3.13.5, Java 17, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Android SDK/build-tools 36, and NDK 28.2.13676358. Install the SDKs on your machine and run `flutter doctor`. Paths are resolved from your toolchain; no original machine path is required.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## Android builds

On PowerShell, `tool/build.ps1` wraps the checks and release targets:

```powershell
.\tool\build.ps1 -Task Check
.\tool\build.ps1 -Task Apk
```

The APK target explicitly opts into local development signing and writes `dist/El-Thanawiya.apk`. A development-signed build is suitable for local testing; physical-device testing remains outstanding.

For an independently distributed release, generate and back up your own upload key, copy `android/key.properties.example` to `android/key.properties`, fill in the private values locally, and run:

```powershell
.\tool\build.ps1 -Task Bundle
```

The bundle is written under `build/app/outputs/bundle/release/`. Signing keys and private property files are ignored by Git. Do not commit them. The existing app has not been submitted to Google Play.

On other shells, run the equivalent Flutter commands. For a local test APK, set `FORMA_LOCAL_SIGNING=true` for that command. Production signing uses your private `android/key.properties`.

## Browser demo

```sh
flutter run -d chrome --dart-define=DEMO=true
```

This uses illustrative sample data and temporary edits. For the packaged preview wrapper, run `tool/build.ps1 -Task Preview` and serve `build/preview` over HTTP with `python -m http.server 3870 --bind 127.0.0.1 --directory build/preview`.

## Model export

From an environment with the Python dependencies installed:

```sh
python tool/export_model.py
flutter test test/model_test.dart
```

The exporter reads the sibling `../academic-risk/model/course_risk.pt` and updates the JSON model and parity fixtures. It does not retrain. Update the checkpoint and its documented checksum deliberately before exporting a new model.

The shipped model matches the Python network's preprocessing, calibration, and threshold. Its validation limits are described in the [model card](../docs/MODEL_CARD.md).
