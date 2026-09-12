# Troubleshooting Guide

Common issues, diagnostics, and resolutions for SejiloChat users and operators.

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Connection Issues](#connection-issues)
3. [Messaging Issues](#messaging-issues)
4. [Performance Issues](#performance-issues)
5. [Privacy & Security Issues](#privacy--security-issues)
6. [Platform-Specific Issues](#platform-specific-issues)
7. [Error Codes](#error-codes)
8. [FAQ](#faq)

---

## Quick Diagnostics

### Is SejiloChat Running?

**Check if the app is active**:
- Android: Look for SejiloChat in the notification bar
- Windows: Check taskbar (should show icon if running)

**Restart the app**:
1. Close SejiloChat completely
2. Wait 5 seconds
3. Relaunch from home screen or app drawer

### Check Bluetooth Status

**Android**:
1. Settings → Connected devices → Bluetooth → toggle on
2. Settings → Apps → SejiloChat → Permissions → Nearby devices (granted?)

**Windows**:
1. Settings → Bluetooth & devices → Bluetooth toggle on
2. Verify BLE adapter appears in Device Manager

### Test Local Network

**Is another device nearby?**
1. Open Mesh tab
2. Tap "Restart nearby scan"
3. Wait 10 seconds for device discovery
4. Check if peers appear

---

## Connection Issues

### Issue: No Nearby Devices Found

**Symptom**: Mesh list is empty; no peers appear even though other devices are running Sejilo nearby.

**Root Causes**:
- [ ] Nearby visibility disabled
- [ ] Bluetooth not enabled
- [ ] Bluetooth permission denied
- [ ] Devices too far apart
- [ ] Bluetooth interference

**Diagnostic Steps**:

1. **Verify nearby visibility is enabled**:
   - Open Mesh tab → Settings (gear icon)
   - Confirm "Visible to nearby devices" toggle is ON
   - Ask the other user to do the same

2. **Verify Bluetooth is on**:
   - Android: Settings → Bluetooth toggle ON
   - Windows: Settings → Bluetooth & devices toggle ON

3. **Verify permissions** (Android):
   - Settings → Apps → SejiloChat → Permissions
   - Check "Nearby devices" is marked "Allowed"
   - Check "Bluetooth" is marked "Allowed"

4. **Check physical range**:
   - Move devices to within 5 meters of each other
   - Typical Bluetooth range is 10–100 meters; obstacles reduce range

5. **Check for interference**:
   - Move away from WiFi router, microwave, or other 2.4 GHz devices
   - Try in an open area

**Resolution**:

If all above checks pass:
- Tap "Restart nearby scan" to manually refresh
- Wait 15 seconds
- If still no peers, restart both apps completely

---

### Issue: Device Drops from Mesh

**Symptom**: Device appeared briefly, then disappeared from the peer list.

**Root Causes**:
- [ ] Peer app was closed or backgrounded
- [ ] Peer device lost Bluetooth connection
- [ ] Peer moved out of range
- [ ] Bluetooth adapter disconnected

**Diagnostic Steps**:

1. **Check peer device status**:
   - Ask the other user if SejiloChat is still running
   - Check that Mesh tab is open (some apps sleep when backgrounded)
   - Verify their Bluetooth is still on

2. **Check physical proximity**:
   - Move devices closer (within 10 meters)
   - Check line of sight (walls reduce Bluetooth range)

3. **Restart scan**:
   - Tap "Restart nearby scan" to force rediscovery
   - Wait 10 seconds

**Resolution**:

- Ask peer to keep app in foreground during communication
- Verify both devices have strong Bluetooth connection
- If recurring, check device Bluetooth driver version (Windows)

---

### Issue: Connection Keeps Dropping

**Symptom**: Peer appears and disappears repeatedly; unstable connection.

**Root Causes**:
- [ ] Bluetooth interference (WiFi, microwaves)
- [ ] Outdated Bluetooth driver
- [ ] Devices moving in/out of range
- [ ] Low battery on peer device

**Diagnostic Steps**:

1. **Check for interference**:
   - Are you near a WiFi router?
   - Is a microwave or cordless phone in use?
   - Move to a different location
   - Disable WiFi temporarily to test

2. **Check driver version** (Windows):
   - Device Manager → Bluetooth → right-click → Properties
   - Note driver version
   - Check manufacturer website for updates

3. **Check battery level**:
   - Ask peer to check their device battery
   - Bluetooth uses significant power; low battery may reduce signal

**Resolution**:

- Update Bluetooth drivers (Windows)
- Move away from interference sources
- Keep devices closer together
- Ask peer to charge their device if battery is low

---

## Messaging Issues

### Issue: Messages Stuck in "Queued" State

**Symptom**: Messages show "🕐 Queued" but never advance to "Sent".

**Root Causes**:
- [ ] No nearby peers available
- [ ] Recipient device offline
- [ ] Message size too large
- [ ] Retry queue full

**Diagnostic Steps**:

1. **Check peer connection**:
   - Open Mesh tab
   - Is the recipient's device listed?
   - If not, add a nearby device first

2. **Check recipient device status**:
   - Ask the recipient if their app is still running
   - Check they are on the same mesh

3. **Check message size**:
   - Attachments have a 10 MB per-file limit
   - Try sending a text message first

4. **Check retry queue**:
   - Wait 1–2 minutes for automatic retry
   - If queue is full, close and reopen the app

**Resolution**:

- Ensure both devices are on the same mesh
- Reduce attachment size
- Restart the app if queue is stuck

### Issue: Messages Not Received

**Symptom**: You sent a message (shows "Sent"), but recipient didn't receive it.

**Root Causes**:
- [ ] Network was interrupted after sending
- [ ] Recipient device was offline
- [ ] Message was never transmitted
- [ ] Recipient blocked you

**Diagnostic Steps**:

1. **Ask the recipient**:
   - Did they see the message in their chat?
   - What delivery state shows on their device?

2. **Check conversation history**:
   - Open the conversation
   - Scroll up to see if message was actually sent

3. **Check if you were blocked**:
   - Try messaging a different peer
   - If that works, you may have been blocked

**Resolution**:

- Re-send the message
- Verify the recipient has your contact verified
- If recurring, ask recipient to check privacy settings

### Issue: Attachment Failed to Send

**Symptom**: Photo or file shows error when sending.

**Root Causes**:
- [ ] File size too large (>10 MB)
- [ ] File format not supported
- [ ] File path broken (file moved/deleted)
- [ ] Insufficient device storage

**Diagnostic Steps**:

1. **Check file size**:
   - File Explorer (Windows) or Files app (Android)
   - Right-click file → Properties → Size
   - Verify it's under 10 MB

2. **Check file format**:
   - Supported: JPEG, PNG, MP4 (videos), M4A (voice notes)
   - Unsupported: RAW, BMP, WAV formats

3. **Check device storage**:
   - Settings → Storage
   - Ensure at least 1 GB free space

**Resolution**:

- Reduce image resolution before sending
- Compress video to smaller size
- Free up device storage

---

## Performance Issues

### Issue: App Crashes on Startup

**Symptom**: SejiloChat crashes immediately after opening; you see a crash dialog.

**Root Causes**:
- [ ] Corrupted app cache
- [ ] Device storage full
- [ ] Incompatible Dart version

**Diagnostic Steps**:

1. **Clear app cache**:
   - Android: Settings → Apps → SejiloChat → Storage → Clear Cache
   - Windows: Delete C:\Users\<user>\AppData\Local\sejilo_chat (backup first)

2. **Check device storage**:
   - Ensure at least 500 MB free space
   - Delete large files or old backups if needed

3. **Check app version**:
   - Open Settings → About SejiloChat
   - Verify you're on the latest version

**Resolution**:

- Clear app cache (step 1)
- Restart device
- Reinstall app if problem persists

### Issue: App Slow or Freezing

**Symptom**: App lags when switching between chats, or freezes for several seconds.

**Root Causes**:
- [ ] Large chat history (1000+ messages)
- [ ] Large attachment library
- [ ] Low device RAM
- [ ] Background processes running

**Diagnostic Steps**:

1. **Check chat size**:
   - Messaging → Long-press large conversation
   - Check message count shown
   - If over 1000, try archiving or deleting old chats

2. **Check available RAM**:
   - Android: Settings → About → Available RAM
   - Windows: Task Manager → Memory
   - If using >75% RAM, close other apps

3. **Check background processes**:
   - Android: Settings → Running services
   - Close apps you don't need

**Resolution**:

- Delete old conversations to reduce chat history
- Close other apps to free up RAM
- Restart the device

---

## Privacy & Security Issues

### Issue: Read Receipts Appearing Unexpectedly

**Symptom**: Peer can see you've read their messages, but you didn't enable read receipts.

**Root Causes**:
- [ ] Read receipts enabled in privacy settings
- [ ] Peer enabled read receipts (affects both directions)

**Diagnostic Steps**:

1. **Check privacy settings**:
   - Profile → Privacy Settings → Read Receipts
   - Note current state

**Resolution**:

- If you disabled read receipts: Wait 30 seconds for sync
- If peer enabled them: You'll see their read status too
- To disable: Profile → Privacy Settings → toggle Read Receipts OFF

### Issue: Attachment Downloaded Without Permission

**Symptom**: Incoming attachment was saved to your device without you clicking anything.

**Root Causes**:
- [ ] Attachment policy set to "Accept All"
- [ ] Auto-download enabled (platform setting)

**Diagnostic Steps**:

1. **Check attachment policy**:
   - Profile → Privacy Settings → Attachment Policy
   - Note current state

**Resolution**:

- Change to "Ask Me" or "Reject All" if you prefer manual downloads
- Profile → Privacy Settings → Attachment Policy → [Select preference]

### Issue: Suspect Message from Known Contact

**Symptom**: Device shows message from a trusted contact, but content seems suspicious or forged.

**Root Causes**:
- [ ] Device was compromised
- [ ] Contact's device was compromised
- [ ] Impersonation (unlikely if verification code checked)

**Diagnostic Steps**:

1. **Check verification code**:
   - Open contact profile
   - Compare verification code with what you verified in person
   - If code changed, device identity changed

2. **Contact the sender**:
   - Use out-of-band method (phone call, SMS)
   - Ask if they sent the message

**Resolution**:

- If code changed: Re-verify the new code before trusting messages
- If sender denies: Block the contact and ask them to reset their device
- If pattern continues: Suspect compromised device

---

## Platform-Specific Issues

### Android Issues

#### Issue: Bluetooth Permission Denied

**Symptom**: "Bluetooth permission denied" error when opening Mesh tab.

**Resolution**:
1. Settings → Apps → SejiloChat → Permissions
2. Toggle "Nearby devices" to ON
3. Restart SejiloChat
4. Tap "Allow" when prompted

#### Issue: Background Bluetooth Scanning Stops

**Symptom**: App works in foreground, but when backgrounded, nearby devices disappear.

**Cause**: Android limits background Bluetooth access to save power.

**Resolution**:
- Keep app in foreground during active communication
- Android 12+: Pin app to taskbar for quick access
- Settings → Battery → Background app refresh (ensure SejiloChat is enabled)

#### Issue: "Location Permission Required"

**Symptom**: App requests location permission, but you haven't enabled Locality Groups.

**Cause**: Bluetooth scanning on Android requires location permission (even though location is not actually accessed).

**Resolution**:
- Tap "Allow" to grant location permission
- Location data is not collected or shared

### Windows Issues

#### Issue: Bluetooth Adapter Not Found

**Symptom**: "No Bluetooth adapter detected" error on Windows startup.

**Cause**: Bluetooth driver not loaded or adapter not installed.

**Resolution**:
1. Device Manager → Bluetooth
2. If Bluetooth adapter appears: Right-click → Restart
3. If Bluetooth adapter missing:
   - Check Device Manager for unknown devices
   - Visit motherboard/laptop manufacturer website
   - Download and install Bluetooth driver

#### Issue: App Won't Start in Background

**Symptom**: App closes when minimized; doesn't appear in system tray.

**Cause**: Windows is terminating background processes.

**Resolution**:
1. Right-click app icon → Pin to Start
2. Settings → Privacy → Background apps
3. Ensure SejiloChat is in the "Allow" list
4. Restart app

---

## Error Codes

| Code | Meaning | Resolution |
|------|---------|-----------|
| **BLE_001** | Bluetooth adapter not found | Install/update Bluetooth driver |
| **BLE_002** | Bluetooth permission denied | Grant Bluetooth permission in Settings |
| **BLE_003** | Bluetooth scanning failed | Restart Bluetooth: Settings → Bluetooth toggle OFF/ON |
| **MSG_001** | Message too large | Reduce attachment size (max 10 MB) |
| **MSG_002** | No route to peer | Ensure peer is on the same mesh network |
| **MSG_003** | Recipient offline | Wait for recipient to come online |
| **CRYPT_001** | Signature verification failed | Message may be corrupted; discard and ask sender to resend |
| **CRYPT_002** | Decryption failed | Session key mismatch; verify contact identity |
| **STORE_001** | Local database corrupted | Restart app; if persists, reinstall |
| **STORE_002** | Insufficient device storage | Free up space: Settings → Storage → Delete files |
| **AUTH_001** | Device identity not found | Reinstall app; warning: loses local chat history |
| **AUTH_002** | Identity verification failed | Re-verify contact codes in person |
| **NET_001** | Relay server unreachable | Check internet connection; verify relay address |
| **NET_002** | Relay server timeout | Try again; relay may be overloaded |

---

## FAQ

### General Questions

**Q: What is SejiloChat?**

A: SejiloChat is a local-first chat app for nearby communication over Bluetooth mesh. No internet, accounts, or servers required.

**Q: Can I use SejiloChat without the internet?**

A: Yes. SejiloChat works completely offline using local Bluetooth. The internet is not required.

**Q: Can I use SejiloChat across the world?**

A: No. SejiloChat only connects to nearby devices (typically 10–100 meters). For long-distance, use Signal, WhatsApp, or similar.

**Q: Is my chat history backed up?**

A: No. All messages are stored locally on your device only. If you reinstall the app or change devices, you lose chat history.

**Q: Can I recover a deleted conversation?**

A: No. Deleted conversations are permanently erased. Plan accordingly; consider archiving instead of deleting.

### Security Questions

**Q: Is my identity private?**

A: Your username and verification code are visible to nearby peers. Your device identity (public key) is only visible to peers you've verified.

**Q: Can someone impersonate me?**

A: Unlikely if contacts verify your verification code in person. If they don't verify, impersonation is possible.

**Q: Are my messages encrypted?**

A: Direct messages are end-to-end encrypted. Public nearby messages are signed but not encrypted.

**Q: Can the app owner read my messages?**

A: No. SejiloChat has no central server or cloud storage. Your messages are only on your device.

**Q: What if my device is lost?**

A: Tap Emergency Data Wipe to reset the app and generate a new identity. An attacker would still need to unlock your device OS to access data.

### Feature Questions

**Q: Can I send files larger than 10 MB?**

A: No. The 10 MB per-attachment limit is enforced for reliability. Consider compressing files before sending.

**Q: Can I have group chats?**

A: Yes, through Locality Groups (geographic areas) or Nearby Chat (broadcast to all peers). One-on-one direct messages are also available.

**Q: Can I make voice calls?**

A: No. You can send text, reactions, and short voice notes. Full voice/video calling is not supported.

**Q: Can I sync chats across my devices?**

A: No. Each device has its own local chat history. Reinstalling or using a different device starts from scratch.

**Q: Can I search across all conversations?**

A: Yes. Tap the Search icon to find messages by keyword. Search is local only (not shared with peers).

### Troubleshooting Questions

**Q: Why don't I see any nearby devices?**

A: Check: (1) Nearby visibility enabled, (2) Bluetooth on, (3) Permissions granted, (4) Devices within range, (5) Tap "Restart nearby scan".

**Q: Why do messages keep getting stuck in "Queued"?**

A: Recipient device is not available. Ensure you have at least one verified contact on the mesh, and the recipient's app is running.

**Q: Why is the app crashing?**

A: Try: (1) Clear cache, (2) Restart device, (3) Reinstall app. If persistent, check device storage.

**Q: Can I use SejiloChat on my PC/Mac?**

A: Only Windows 10+. Mac support is not available. Consider running Windows in a VM if needed.

**Q: How do I report a bug?**

A: Profile → Settings → Report an Issue. Include detailed description and steps to reproduce.

---

## Advanced Troubleshooting

### Collect Logs for Debugging

**Android**:
1. Profile → Settings → Advanced
2. Tap "Export Logs"
3. Share log file with support

**Windows**:
1. Navigate to `C:\Users\<user>\AppData\Local\sejilo_chat\logs`
2. Attach latest log file to issue report

### Check Bluetooth Signal Strength

**Android**:
1. Developer Settings → Enable Bluetooth HCI snoop log
2. Use Android Studio → Android Profiler to view signal strength

**Windows**:
1. Device Manager → Bluetooth adapter → Properties
2. Check signal strength indicator

---

## Need More Help?

- **In-App Help**: Profile → Settings → Help
- **Report Issue**: Profile → Settings → Report an Issue
- **Community**: Check the project repository for discussions
- **Docs**: Reference SECURITY_PRIVACY.md, USER_GUIDE.md, API_REFERENCE.md

---

## Version Information

- **Guide Version**: 1.0
- **SejiloChat App**: 0.5.0+
- **Last Updated**: August 2024
