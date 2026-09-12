# SejiloChat

SejiloChat is a local-first Bluetooth mesh chat for Android and Windows. It is designed for nearby communication when the internet is unavailable: no account, phone number, server, or cloud connection is required.

## What it does

- Creates a separate local device identity and clean chat vault for each installation.
- Finds nearby Sejilo peers over Bluetooth Low Energy and exchanges signed mesh messages.
- Supports public nearby chat, verified friend chats, locality groups, message reactions, search, pins, photos, and short voice notes.
- Stores chat history locally in encrypted device storage and keeps message content out of operational logs.
- Includes delivery state, retry/queue behaviour, local notification support, and a compact verification code for comparing identities in person.

## Use nearby mesh

1. Install the same current release on both devices.
2. Create a username on each device.
3. Open **Mesh**, allow **Nearby devices/Bluetooth** on Android, then turn on **Visible to nearby devices** on both devices.
4. Keep the app open for the first connection. A nearby peer should appear in the Mesh list.
5. If a device has just granted permission, resumed from sleep, or Bluetooth was toggled, use **Restart nearby scan**.

Windows requires a Bluetooth LE adapter. Some Windows adapters can scan and connect but cannot host the GATT advertising service; Sejilo will continue scanning in that case. Android 12+ requires Nearby devices permission; location is only requested for optional locality group naming.

## Build from source

Requirements: Flutter SDK, Android SDK for APK builds, and Visual Studio with Desktop development with C++ for Windows builds.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

Android output: `build/app/outputs/flutter-apk/app-release.apk`  
Windows output: `build/windows/x64/runner/Release/`

For Windows, distribute the entire release folder (or the supplied portable ZIP), not only `sejilo_chat.exe`; it needs the adjacent DLLs and data folder.

## Privacy and security notes

Bluetooth mesh traffic is local and messages are signed to detect tampering and replay. Direct-message end-to-end session encryption and an independent security audit are not complete, so do not use the app for sensitive information. The app does not replace emergency communications.
