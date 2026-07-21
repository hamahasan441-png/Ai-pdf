# AI PDF — Release Signing Guide

## Overview

Android requires APKs/App Bundles to be signed with a cryptographic key before
they can be uploaded to the Play Store. This project uses a **CI-friendly
configuration** where the keystore and credentials are stored as GitHub Secrets,
and the build workflow injects them automatically.

---

## Local Development

For local development, `flutter build apk` works without signing configuration —
it falls back to the debug keystore automatically (configured in
`frontend/android/app/build.gradle` via the `hasReleaseKeystore` flag).

---

## CI Setup (One-time)

### 1. Generate the Upload Keystore

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass YOUR_STORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD \
  -dname "CN=AI PDF, OU=Mobile, O=AiDocAssistant, L=City, ST=State, C=US"
```

### 2. Base64-encode the Keystore

```bash
base64 -w 0 upload-keystore.jks > upload-keystore.b64
```

### 3. Add GitHub Secrets

In the repository settings → Secrets and variables → Actions, add:

| Secret Name | Value |
|-------------|-------|
| `KEYSTORE_BASE64` | Contents of `upload-keystore.b64` |
| `KEYSTORE_PASSWORD` | The store password used above |
| `KEY_ALIAS` | `upload` |
| `KEY_PASSWORD` | The key password used above |

### 4. CI Workflow (Already Configured)

The `build-apk.yml` workflow has a "Decode keystore" step that:
1. Decodes the base64 keystore into `frontend/android/upload-keystore.jks`
2. Creates `frontend/android/key.properties` with the credentials
3. `build.gradle` detects `key.properties` and uses it for release signing

If the secrets are not set (e.g. on a fork or in a PR from an outside
contributor), the build gracefully falls back to debug signing.

---

## Security Notes

- **Never commit** `upload-keystore.jks` or `key.properties` to the repository.
- Both are in `.gitignore`.
- The keystore is decoded only in the CI runner's ephemeral environment.
- Play App Signing further protects the actual distribution key: the upload key
  only signs what you upload; Google re-signs with the app signing key.

---

## Verifying a Signed APK

```bash
# Check the signature
apksigner verify --print-certs AI-PDF.apk

# Or with jarsigner
jarsigner -verify -verbose -certs AI-PDF.apk
```

---

## Play App Signing

Google Play uses **Play App Signing** by default for new apps. Your upload key
signs the artifact you upload; Google then re-signs it with a Google-managed app
signing key for distribution. This means:

- If you lose the upload key, you can request a reset from Google.
- The distribution key is more secure (stored in Google's infrastructure).
- You still need the upload key for CI uploads.
