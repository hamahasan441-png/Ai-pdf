# How to Build the APK

## Option 1: Automatic (GitHub Actions) — RECOMMENDED

The APK builds automatically when you push to `main`.

1. Push code to GitHub
2. Go to **Actions** tab → "Build Android APK"
3. Wait for the build to complete (~5 min)
4. Download the APK from the **Artifacts** section

## Option 2: Build Locally

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x)
- [Android Studio](https://developer.android.com/studio) or Android SDK
- Java 17

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/hamahasan441-png/Ai-pdf.git
cd Ai-pdf/frontend

# 2. Get dependencies
flutter pub get

# 3. Build release APK
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Build split APKs (smaller, per architecture)

```bash
flutter build apk --split-per-abi --release
```

This produces:
- `app-arm64-v8a-release.apk` (~15MB) — Most modern phones
- `app-armeabi-v7a-release.apk` (~14MB) — Older phones
- `app-x86_64-release.apk` — Emulators

### Install on device

```bash
# Via USB
flutter install

# Or manually
adb install build/app/outputs/flutter-apk/app-release.apk
```

## Option 3: Build with App Bundle (for Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

## Configuration

Before building, you can change the backend URL:

```bash
# Point to your server
flutter build apk --release --dart-define=API_BASE_URL=https://your-server.com/api/v1
```

## Troubleshooting

### "SDK not found"
Run: `flutter doctor` and fix any issues

### "Gradle build failed"
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk --release
```

### App crashes on startup
Make sure the backend is running and accessible from the device.
For local dev: use `http://YOUR_IP:8000/api/v1` instead of `localhost`.
