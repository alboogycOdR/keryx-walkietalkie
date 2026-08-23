# Release signing (TASK-039)

Production Play / sideload builds must be signed with an upload keystore
that **does not live in git**. The debug keystore is a development fallback
so `flutter build apk --release` still succeeds on a clean checkout.

## Template

1. Copy `android/key.properties.example` → `android/key.properties`.
2. Generate a keystore **outside** the tree:

   ```powershell
   keytool -genkey -v `
     -keystore $env:USERPROFILE\keryx-upload.jks `
     -keyalg RSA -keysize 2048 -validity 10000 `
     -alias upload
   ```

3. Fill `storePassword`, `keyPassword`, `keyAlias`, `storeFile` in
   `key.properties`. `storeFile` may be an absolute path (preferred) or a
   path relative to `android/app/`.

4. Confirm Git refuses the secrets (from repo root):

   ```powershell
   git check-ignore -v android/key.properties
   git check-ignore -v android/upload-keystore.jks
   ```

   Both must print a matching `android/.gitignore` rule. If either is
   untracked in `git status`, stop — do not commit.

## What Gradle does

`android/app/build.gradle.kts`:

- If `android/key.properties` exists, the `release` signing config uses it.
- If it is absent, the `release` build type falls back to the debug
  keystore and prints a warning. That APK is installable for the two-phone
  field test; it is **not** a Play upload.

No real passwords, aliases, or `.jks` files belong in this repository.
