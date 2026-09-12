# Android release signing

Release builds fail closed when a production signing key is unavailable. Never
commit a keystore or its passwords. Configure the CI secret store with:

- `SEJILO_ANDROID_KEYSTORE`: absolute path to the CI-provided keystore
- `SEJILO_ANDROID_KEY_ALIAS`
- `SEJILO_ANDROID_STORE_PASSWORD`
- `SEJILO_ANDROID_KEY_PASSWORD`

Build with `flutter build appbundle --release`. Protect and back up the signing
key offline, restrict CI access, and prepare a signing-key compromise rotation
procedure before distribution. Debug builds remain available for development.
