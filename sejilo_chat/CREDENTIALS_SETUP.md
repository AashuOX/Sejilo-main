# SejiloChat Credential Provisioning Guide

This guide walks you through setting up and configuring all required external credentials for SejiloChat's cloud features: Google OAuth, Firebase Cloud Messaging, Twilio SMS, and AWS S3 storage.

## Overview

SejiloChat supports optional online features that require external service credentials:

| Service | Purpose | Required For | Status |
|---------|---------|--------------|--------|
| **Google OAuth** | User sign-in & profile import | Account authentication | Optional |
| **Firebase** | Push notifications to offline users | Live delivery / FCM | Optional |
| **Twilio** | Phone number verification & SMS OTP | Phone-based auth | Optional |
| **AWS S3** | Image/media storage in cloud | Post media persistence | Optional |

All services are optional. SejiloChat operates fully offline with local Bluetooth mesh without any credentials.

---

## 1. Google OAuth Setup

### 1.1 Create GCP Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click **Select a Project** → **New Project**
3. Enter project name: `SejiloChat` (or your app name)
4. Click **Create**
5. Wait for the project to initialize (1-2 minutes)

### 1.2 Enable Google Sign-In API

Nothing needs enabling. This app sends a Google **ID token** to its own backend,
which verifies the token's signature and audience against Google's public keys —
it calls no Google API on your project's behalf, so there is no API to turn on.
(The old "Google+ API" instruction is obsolete; that API was shut down in 2019.)

`docs/GOOGLE_SIGNIN.md` is the authoritative walkthrough for this flow, including
the fingerprints to register and every failure signature. This section is the
short version.

### 1.3 Create OAuth 2.0 Credentials

Two clients must exist in the same project. Missing either one is the usual cause
of a sign-in that fails before any token exists.

1. Go to **APIs & Services** → **Credentials**
2. If prompted, configure the **OAuth consent screen** first:
   - Select **External**
   - App name: `SejiloChat`; user support email and developer contact: your email
   - On "Scopes" → **Save and Continue**
   - While the app is unpublished, add every tester under **Audience → Test
     users**, or their sign-in is refused
3. Create the **Web** client — this is the one the code names:
   - **+ Create Credentials** → **OAuth client ID** → **Web application**
   - Name: `SejiloChat Web Client`
   - Leave **Authorized redirect URIs** empty. There is no browser redirect in
     this flow: the Android plugin returns the ID token in-process. (The app
     registers no custom URL scheme, so a redirect could not come back to it.)
4. Create the **Android** client — never named in code, but required for the
   plugin to mint a token at all:
   - **+ Create Credentials** → **OAuth client ID** → **Android**
   - Package name: `com.sejilochat.app`
   - SHA-1: add **both** the debug and the release fingerprint (see
     `docs/GOOGLE_SIGNIN.md` for the values and how to re-derive them)

5. Copy the credentials:
   - **Client ID** (from the *Web* client) → `GOOGLE_CLIENT_ID` on the server, and
     it must equal `AccountAuthController.googleServerClientId` in the app
   - **Client Secret** → nowhere. This design never exchanges an authorization
     code, so nothing reads a secret; storing one only creates a credential to
     leak. If you have already copied one, rotate it in the console.

### 1.4 Create Service Account (for backend)

1. Go to **APIs & Services** → **Credentials**
2. Click **+ Create Credentials** → **Service Account**
3. Fill in:
   - Service account name: `SejiloChat Backend`
   - Service account ID: `sejilo-chat-backend`
4. Click **Create and Continue**
5. Grant roles: **Editor** (for development)
6. Click **Continue** then **Done**

7. Create a key:
   - Click on the service account email
   - Go to **Keys** tab
   - Click **Add Key** → **Create new key**
   - Format: **JSON**
   - Click **Create** (JSON file downloads automatically)

8. Add to `.env`:
   ```
   GOOGLE_SERVICE_ACCOUNT_JSON=/path/to/downloaded/json
   ```

### 1.5 Validation Checklist

- [ ] OAuth Client ID set: `echo $GOOGLE_CLIENT_ID`
- [ ] No client secret stored anywhere: `grep -r GOCSPX- .` returns nothing
- [ ] Android OAuth client exists for `com.sejilochat.app` with both SHA-1s
- [ ] Web client id in the app equals `GOOGLE_CLIENT_ID` on the server
- [ ] Service Account JSON file exists and is readable

**Test command** — proves the server half without a phone. A `401` means the
audience is configured and this junk token simply failed verification, which is
the healthy answer; `503` means `GOOGLE_CLIENT_ID` is unset on the server:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://sejilo-backend.onrender.com/v1/auth/google -H 'content-type: application/json' -d '{"idToken":"not.a.real.token"}'
```

---

## 2. Firebase Setup

### 2.1 Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add project**
3. Enter project name: `SejiloChat` (can be same as GCP project)
4. Disable Google Analytics (optional)
5. Click **Create project**
6. Wait for initialization

### 2.2 Enable Cloud Messaging (FCM)

1. In Firebase Console, go to **Project Settings** (gear icon)
2. Go to **Cloud Messaging** tab
3. Enable **Firebase Cloud Messaging API** in GCP
4. Copy the **Server API Key** → `FIREBASE_SERVER_KEY`
5. Copy the **Sender ID** → `FIREBASE_SENDER_ID`

### 2.3 Download Service Account JSON

1. In Firebase Console, click **Project Settings** → **Service Accounts**
2. Click **Generate New Private Key**
3. JSON file downloads automatically
4. Save to secure location: `/path/to/firebase-key.json`

5. Add to `.env`:
   ```
   FIREBASE_SERVICE_ACCOUNT_JSON=/path/to/firebase-key.json
   FIREBASE_SERVER_KEY=your_server_key_here
   FIREBASE_SENDER_ID=your_sender_id_here
   ```

### 2.4 Create Web App Registration

1. In Firebase Console, click **Project Settings** → **Your apps**
2. Click **Web** (+ icon)
3. Register app name: `SejiloChat Web`
4. Copy the Firebase config:
   ```javascript
   {
     "apiKey": "...",
     "authDomain": "...",
     "projectId": "...",
     "storageBucket": "...",
     "messagingSenderId": "...",
     "appId": "..."
   }
   ```
5. Add to `.env`:
   ```
   FIREBASE_API_KEY=your_api_key
   FIREBASE_PROJECT_ID=your_project_id
   FIREBASE_MESSAGING_SENDER_ID=your_sender_id
   ```

### 2.5 Enable Firestore (Optional, for data sync)

1. In Firebase Console, go to **Firestore Database**
2. Click **Create Database**
3. Start in **Test mode** (development only)
4. Choose region: closest to your users
5. Click **Create**

### 2.6 Validation Checklist

- [ ] Service Account JSON file exists and readable
- [ ] `FIREBASE_SERVER_KEY` is set
- [ ] `FIREBASE_SENDER_ID` is set
- [ ] Firebase API enabled in GCP
- [ ] Web app configuration retrieved

**Test command:**
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$FIREBASE_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"to":"test_token","data":{"test":"1"}}'
```

---

## 3. Twilio Setup

### 3.1 Create Twilio Account

1. Go to [Twilio Console](https://www.twilio.com/console)
2. Sign up for a free account (includes $15 trial credit)
3. Verify your phone number (required for SMS)
4. Go to **Account** → **API Keys & Tokens**

### 3.2 Get API Credentials

1. In Twilio Console, copy:
   - **Account SID** → `TWILIO_ACCOUNT_SID`
   - **Auth Token** → `TWILIO_AUTH_TOKEN`

2. Add to `.env`:
   ```
   TWILIO_ACCOUNT_SID=your_account_sid
   TWILIO_AUTH_TOKEN=your_auth_token
   ```

### 3.3 Buy a Phone Number (for sending SMS)

1. Go to **Phone Numbers** → **Buy a Number**
2. Select your country
3. Choose features: **SMS** (required), Voice (optional)
4. Select a number and click **Buy**
5. Complete payment
6. Go back to **Phone Numbers** → **Active Numbers**
7. Copy the number → `TWILIO_PHONE_NUMBER`

8. Add to `.env`:
   ```
   TWILIO_PHONE_NUMBER=+1234567890  # Replace with your number
   ```

### 3.4 Setup SMS Webhook (for incoming SMS notifications)

1. In Twilio Console, go to **Phone Numbers** → **Active Numbers**
2. Click on your purchased number
3. Under **Messaging** section:
   - **A Message Comes In** → **Webhook**
   - URL: `https://yourdomain.com/webhooks/twilio/sms`
   - HTTP POST
   - Save

### 3.5 Validation Checklist

- [ ] `TWILIO_ACCOUNT_SID` is set
- [ ] `TWILIO_AUTH_TOKEN` is set
- [ ] `TWILIO_PHONE_NUMBER` is set and includes country code
- [ ] Phone number is active in Twilio Console
- [ ] Account has SMS capability (not just voice)

**Test command:**
```bash
curl -X POST https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json \
  -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
  -d "From=$TWILIO_PHONE_NUMBER" \
  -d "To=+1234567890" \
  -d "Body=Test message"
```

---

## 4. AWS S3 Setup

### 4.1 Create AWS Account

1. Go to [AWS Console](https://aws.amazon.com/console)
2. Sign up for AWS account
3. Complete identity verification
4. Set up billing (even free tier requires payment method)

### 4.2 Create IAM User for S3 Access

1. Go to **IAM Console** → **Users**
2. Click **Create user**
3. Username: `sejilo-chat-s3`
4. Uncheck "AWS Management Console access"
5. Click **Next**
6. Click **Attach policies directly**
7. Search for and select: **AmazonS3FullAccess**
8. Click **Next** → **Create user**

### 4.3 Generate Access Keys

1. Click on the user you just created
2. Go to **Security credentials** tab
3. Under **Access keys**, click **Create access key**
4. Choose **Application running outside AWS** (or Local code)
5. Click **Next**
6. Copy:
   - **Access Key ID** → `AWS_ACCESS_KEY_ID`
   - **Secret Access Key** → `AWS_SECRET_ACCESS_KEY`

7. Add to `.env`:
   ```
   AWS_ACCESS_KEY_ID=your_access_key
   AWS_SECRET_ACCESS_KEY=your_secret_key
   AWS_REGION=us-east-1
   ```

### 4.4 Create S3 Bucket

1. Go to **S3** → **Buckets**
2. Click **Create bucket**
3. Bucket name: `sejilo-chat-media-prod` (must be globally unique)
4. Region: Your preferred region
5. Uncheck "Block all public access" (optional, for public image URLs)
6. Click **Create bucket**

7. Add to `.env`:
   ```
   AWS_S3_BUCKET=sejilo-chat-media-prod
   AWS_S3_REGION=us-east-1
   ```

### 4.5 Configure CORS (for browser uploads)

1. Click on your bucket
2. Go to **Permissions** → **CORS**
3. Click **Edit**
4. Add this policy:
   ```json
   [
     {
       "AllowedHeaders": ["*"],
       "AllowedMethods": ["GET", "PUT", "POST"],
       "AllowedOrigins": ["https://yourdomain.com", "http://localhost:3000"],
       "ExposeHeaders": ["ETag"],
       "MaxAgeSeconds": 3000
     }
   ]
   ```
5. Click **Save changes**

### 4.6 Setup Bucket Lifecycle (Optional, for cleanup)

1. Click on your bucket
2. Go to **Management** → **Lifecycle rules**
3. Click **Create lifecycle rule**
4. Name: `DeleteOldMedia`
5. Under "Expire current versions of objects":
   - Enable it
   - Days: `90` (delete after 90 days)
6. Click **Create rule**

### 4.7 Validation Checklist

- [ ] `AWS_ACCESS_KEY_ID` is set
- [ ] `AWS_SECRET_ACCESS_KEY` is set
- [ ] `AWS_S3_BUCKET` exists and is readable
- [ ] `AWS_REGION` is correctly set
- [ ] IAM user has S3 permissions

**Test command:**
```bash
aws s3 ls s3://$AWS_S3_BUCKET --region $AWS_REGION
```

---

## Environment Variables Reference

Create or update `.env` file in project root with all credentials:

```bash
# Google OAuth (server-side; no client secret — see 1.3)
GOOGLE_CLIENT_ID=your_client_id.apps.googleusercontent.com
GOOGLE_SERVICE_ACCOUNT_JSON=/path/to/google-service-account.json

# Firebase
FIREBASE_SERVICE_ACCOUNT_JSON=/path/to/firebase-key.json
FIREBASE_SERVER_KEY=your_server_key
FIREBASE_SENDER_ID=123456789
FIREBASE_API_KEY=your_api_key
FIREBASE_PROJECT_ID=sejilo-chat-xxxxx
FIREBASE_MESSAGING_SENDER_ID=123456789

# Twilio
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_PHONE_NUMBER=+1234567890

# AWS S3
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_S3_BUCKET=sejilo-chat-media-prod
AWS_REGION=us-east-1
```

---

## Local Development Workarounds

### Mock Firebase (for development without FCM)

Set in `.env`:
```bash
FIREBASE_MOCK=true
FIREBASE_LOG_MESSAGES=true
```

The backend will log push notifications instead of sending them via FCM.

### File-based S3 Storage (local dev)

Set in `.env`:
```bash
AWS_MOCK=true
AWS_LOCAL_STORAGE_PATH=/tmp/sejilo-media
```

Images are stored locally instead of uploaded to S3.

### Twilio SMS Console Output

Set in `.env`:
```bash
TWILIO_MOCK=true
TWILIO_LOG_SMS=true
```

SMS messages are logged to console instead of being sent.

### Skip OAuth Verification in Dev

Set in `.env`:
```bash
GOOGLE_OAUTH_SKIP_VERIFY=true
```

Only use in development. Never enable in production.

---

## Security Best Practices

1. **Never commit `.env` files** to git
2. **Rotate credentials regularly** (every 90 days recommended)
3. **Use IAM roles instead of keys** when possible in AWS
4. **Enable MFA** on all cloud accounts
5. **Restrict API key permissions** to minimum required
6. **Use separate credentials for dev/prod/staging**
7. **Store secrets in a secrets manager** (AWS Secrets Manager, HashiCorp Vault, etc.)
8. **Audit credential usage** regularly in cloud console logs

---

## Troubleshooting

### "Invalid OAuth credentials"
- Verify `GOOGLE_CLIENT_ID` on the server equals the id compiled into the app
  (`AccountAuthController.googleServerClientId`). A mismatch logs
  `Wrong recipient` and answers `401`; there is no client secret to check.
- Ensure the Android OAuth client exists for `com.sejilochat.app` with the SHA-1
  of the keystore that signed the build, or the plugin fails with
  `ApiException: 10` before a token is ever minted
- Ensure the OAuth consent screen is configured, and that the account is listed
  under Test users while the app is unpublished

### "FCM token validation failed"
- Verify `FIREBASE_SERVER_KEY` is set to Cloud Messaging key (not API key)
- Confirm Firebase service account JSON is valid and readable
- Check Firebase Cloud Messaging API is enabled in GCP

### "Twilio authentication failed"
- Verify `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN` are correct
- Ensure account is active (check Twilio Console)
- Verify `TWILIO_PHONE_NUMBER` is active and SMS-capable

### "S3 access denied"
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are correct
- Ensure IAM user has `AmazonS3FullAccess` policy
- Check bucket name is correct in `AWS_S3_BUCKET`
- Verify region matches bucket location

---

## Next Steps

1. Complete all credential setup steps above
2. Run validation script: `bash scripts/validate-credentials.sh`
3. Run live delivery test: `node scripts/test-live-delivery.js`
4. Review generated credential test report
5. Enable features in UI based on availability

See [CREDENTIALS_SETUP.md](./CREDENTIALS_SETUP.md) for detailed setup instructions.
