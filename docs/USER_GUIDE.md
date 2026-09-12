# SejiloChat User Guide

Welcome to SejiloChat — a local-first, privacy-focused mesh chat for nearby communication without internet, accounts, or servers.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Creating Your Identity](#creating-your-identity)
3. [Mesh Networking Setup](#mesh-networking-setup)
4. [Core Features](#core-features)
5. [Privacy Settings](#privacy-settings)
6. [Troubleshooting](#troubleshooting)

---

## Getting Started

### System Requirements

- **Android**: Android 12 or later, Bluetooth Low Energy (BLE) support
- **Windows**: Windows 10 or later, Bluetooth LE adapter

### Installation

1. Download SejiloChat for your platform
   - Android: Install APK from the official source
   - Windows: Extract the release folder (do not move individual files)
2. Launch the app
3. Grant required permissions when prompted:
   - **Android**: Nearby devices/Bluetooth permission (required for mesh discovery)
   - **Windows**: No special permissions required

### First Launch

On first startup, SejiloChat creates:
- **Device Identity**: A unique cryptographic identity for your device
- **Chat Vault**: An encrypted local storage for all messages
- **Verification Code**: A human-readable code for safely comparing identities with friends

```
Your device is now ready for local mesh communication.
No internet connection required.
No account or personal information needed.
```

---

## Creating Your Identity

### Username Setup

During initial setup, create a username that represents you on the mesh:

1. Open the app → **Profile Setup**
2. Enter your desired **Username** (required):
   - 3–32 characters, alphanumeric and underscores
   - Visible to nearby peers
   - Cannot be changed once created (new username requires reinstalling)
3. Optionally add a **Display Name** (full name, nickname, organization)
4. Tap **Create Profile**

### Your Verification Code

Your verification code is a 6-character string displayed under your username:

```
Example: JKPM-2B
```

**This code uniquely identifies you.** Share it with trusted friends to verify identities in person before chatting. Compare codes face-to-face to ensure you're not talking to an impostor.

### Viewing Your Identity

- **Profile Screen**: Shows your username, display name, and verification code
- **QR Code**: Tap to display a QR code for your device identity
  - Scan to verify contact information with others
  - Keep this private; others can use it to add you as a contact

---

## Mesh Networking Setup

### Understanding Mesh

Sejilo creates a **local mesh network** over Bluetooth Low Energy:

- **Mesh Nodes**: Each device running Sejilo
- **Nearby Range**: Typically 10–100 meters (varies by hardware)
- **Store-and-Forward**: Devices relay messages to extend range
- **No Server**: All communication stays on-device

```
Device A ←→ Device B
            ↓
         Device C
```

### Enable Nearby Visibility

1. Open **Mesh** tab
2. Tap **Settings** (gear icon)
3. Enable **"Visible to nearby devices"**
4. Allow Bluetooth permission if prompted

#### Android-Specific Steps

1. Grant **Nearby devices** permission:
   - Settings → Apps → SejiloChat → Permissions → Nearby devices
2. Grant **Location** permission (optional, only for locality group naming):
   - Settings → Apps → SejiloChat → Permissions → Location

#### Windows-Specific Notes

- Ensure Bluetooth is turned on in Windows Settings
- Some Bluetooth adapters can scan but not advertise; Sejilo will continue scanning
- Keep the app in focus during initial connections

### Discover Nearby Peers

1. Open **Mesh** tab
2. Wait 5–10 seconds for discovery
3. Nearby peers appear in the **Peers list**

**If no peers appear:**
- Tap **Restart nearby scan** to refresh
- Verify other devices have **Visible to nearby devices** enabled
- Check that devices are within Bluetooth range
- For Android, verify Bluetooth and Nearby permissions are granted

### Add a Contact

1. Find the peer in the **Mesh** list
2. Tap the peer to view their profile
3. Tap **Add as Contact** to start a verified chat
4. Compare **Verification Codes** with them in person to confirm identity

---

## Core Features

### Messaging

#### Send a Message

1. Open **Messaging** tab
2. Select a conversation or tap a peer in **Mesh** to start a new chat
3. Type your message in the text field
4. Tap **Send** (paper plane icon)

**Delivery States:**
- 🕐 **Queued**: Waiting to send
- 📤 **Sent**: Delivered to nearby peer
- ✓ **Received**: Peer has accepted the message
- ✓✓ **Read**: Peer has viewed the message (if enabled)

#### Message Types

**Text Messages**
- Unlimited length
- Supported on all platforms

**Attachments**
- Photos and images (JPEG, PNG)
- Voice notes (up to 5 minutes)
- File size limits: 10 MB per attachment

**Reactions**
- React to messages with emoji
- Tap the message → **React** → select emoji
- Reactions are end-to-end encrypted

### Conversations

#### Manage Conversations

1. Open **Messaging** tab
2. Long-press a conversation to see options:
   - **Archive**: Hide without deleting
   - **Mute**: Suppress notifications
   - **Delete**: Permanently remove (local only)

#### Conversation Types

- **Direct Messages**: One-on-one encrypted chats with verified contacts
- **Nearby Chat**: Public messages visible to all peers in mesh
- **Locality Groups**: Messages scoped to your geographic area (if enabled)

### Pins & Reactions

#### Pin Important Messages

1. Open the message
2. Tap **More** (⋯)
3. Select **Pin**
4. Pinned messages appear at the top of the conversation

#### React to Messages

1. Tap and hold a message
2. Select **React**
3. Choose an emoji from the picker
4. Tap to add the reaction

### Search

Use **Search** to find messages by content:

1. Open **Messaging** tab
2. Tap the **Search** icon (magnifying glass)
3. Type keywords
4. Results show matching messages from all conversations

**Note**: Searches only match local message content; remote peers cannot search your messages.

---

## Privacy Settings

### Enable Privacy Controls

1. Open **Profile** tab
2. Tap **Privacy Settings**

### Available Controls

#### Message Encryption

- **Direct Messages**: Automatically end-to-end encrypted
- **Public Messages**: Signed but not encrypted (visible to all peers)
- **Voice Notes**: Encrypted when sent to a specific contact

#### Read Receipts

- **Disabled (Default)**: Peers cannot see if you've read their messages
- **Enabled**: Peers see read status in direct messages
- **Toggle**: Privacy Settings → **Read Receipts**

#### Attachment Policy

- **Accept All**: Receive all attachments
- **Ask Me**: Prompt before downloading large attachments
- **Reject All**: Do not download attachments (metadata only)

#### Clear Local History

Permanently delete all local message data:

1. Privacy Settings → **Clear Chat History**
2. Confirm deletion
3. All local messages are securely erased
4. **Cannot be undone**

#### Panic Wipe

In an emergency, wipe all app data:

1. Privacy Settings → **Emergency Data Wipe**
2. Confirm multiple times
3. App is reset to clean state
4. Device identity is changed

### Data Retention

SejiloChat stores only:

- Your messages and reactions (encrypted locally)
- Peer identities (public keys, verification codes)
- Conversation metadata (timestamps, delivery state)

SejiloChat does **not** store:

- Your IP address or location
- Bluetooth MAC addresses permanently
- Browsing history or external activity
- Telemetry or usage analytics

---

## Common Tasks

### Verify a Friend's Identity

1. Ask your friend for their **Verification Code** (e.g., JKPM-2B)
2. Open their profile in **Mesh**
3. Compare the code shown on screen with what they told you
4. If codes match, you can safely add them as a contact
5. All future messages are cryptographically pinned to that identity

### Export Your Conversations

Currently, SejiloChat does not support built-in export. To preserve chats:

1. Take screenshots of important conversations
2. Use device backup features:
   - **Android**: Google One backup includes app data
   - **Windows**: File Explorer → AppData → Local → sejilo_chat (manual backup)

### Change Your Username

To use a new username:

1. Open **Privacy Settings**
2. Tap **Reset Profile**
3. Reinstall the app
4. Create a new username during setup

### Disable Notifications

1. Open **Profile** → **Settings**
2. Toggle **Notifications** off
3. You still receive messages; they appear when you open the app

---

## Troubleshooting

### Peers Not Appearing

**Problem**: No nearby devices show in the Mesh list

**Solutions**:
1. Check that nearby devices have **Visible to nearby devices** enabled
2. On Android, grant **Nearby devices** permission: Settings → Apps → SejiloChat → Permissions
3. Verify Bluetooth is on and working
4. Tap **Restart nearby scan** to force rediscovery
5. Move devices closer (within 10–20 meters)
6. Keep the app in foreground on both devices for 10–15 seconds

### Messages Not Sending

**Problem**: Messages stay in "Queued" state

**Causes & Solutions**:
- **No nearby peers**: Add a nearby device to the mesh (see Mesh Networking Setup)
- **Peer offline**: The recipient device is not running Sejilo or lost connection
- **Message too large**: Reduce attachment size (limit is 10 MB)
- **Retry queue full**: Wait a few minutes and try again
- **Bug**: Force close and relaunch the app

### Bluetooth Keeps Disconnecting

**Problem**: Connection drops frequently

**Solutions**:
1. On Windows, ensure the Bluetooth adapter driver is up-to-date
2. On Android, disable WiFi and check if the problem persists (interference)
3. Restart Bluetooth: Toggle off, wait 5 seconds, toggle on
4. Move closer to the other device
5. Reduce interference: Keep devices away from microwaves and WiFi routers

### App Crashes on Startup

**Problem**: SejiloChat crashes immediately after launch

**Solutions**:
1. Force close: Settings → Apps → SejiloChat → Force Stop
2. Clear app cache: Settings → Apps → SejiloChat → Storage → Clear Cache
3. Restart your device
4. Reinstall the app (warns about losing local chat history)

### Large Attachments Not Transferring

**Problem**: Photos or files fail to send

**Solutions**:
- Check file size (max 10 MB per attachment)
- Ensure recipient is nearby and connected
- Try sending a smaller file first
- Restart the app and retry

---

## Tips & Best Practices

### For Everyday Use

- **Keep the app open** during first connections to establish trust relationships
- **Compare verification codes** in person before adding contacts for security
- **Use search** to find old conversations quickly
- **Pin important messages** for easy reference

### For Group Communication

- Use **Locality Groups** to organize messages by geographic area
- In **Nearby Chat**, prefix messages with context (e.g., "@groceries What time?")

### For Security

- **Never share your verification code** unless verifying identity
- **Review privacy settings** after installation
- **Disable read receipts** if you prefer privacy
- **Use the panic wipe** if your device is lost or compromised

### For Emergencies

- SejiloChat does **not** replace emergency services
- For life-threatening situations, call 911 or local emergency services
- Use Sejilo for local coordination only

---

## Getting Help

### In-App Support

- Tap **Help** from the **Profile** tab for FAQs and troubleshooting
- Check the **Troubleshooting** section in this guide

### Reporting Issues

1. Open **Profile** → **Settings**
2. Tap **Report an Issue**
3. Describe the problem and attach logs if available
4. Submit feedback to the development team

### Known Limitations

- **No internet relay**: Only works with nearby devices on Bluetooth mesh
- **Background mode limited**: Some platforms may pause scanning when app is backgrounded
- **End-to-end encryption incomplete**: Direct messages use authenticated encryption; full review pending
- **No group chats**: Only direct messages and public nearby chat
- **No voice calls**: Text, reactions, and voice notes only

---

## Version Information

- **Current Version**: 0.5.0
- **Platforms**: Android 12+, Windows 10+
- **Build Date**: August 2024

For the latest updates and release notes, visit the project repository.
