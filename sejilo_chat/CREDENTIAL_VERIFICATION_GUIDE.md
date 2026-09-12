# SejiloChat Credential Provisioning & Verification System

## 📋 Overview

Complete credential provisioning system for SejiloChat cloud features including Google OAuth, Firebase Cloud Messaging, Twilio SMS, and AWS S3 storage.

### What's Included

1. **CREDENTIALS_SETUP.md** - Comprehensive step-by-step setup guides for all services
2. **scripts/validate-credentials.sh** - Automated credential validation script
3. **scripts/test-live-delivery.js** - End-to-end cloud feature test suite
4. **.env.example** - Template for environment variables

---

## 🚀 Quick Start

### 1. Setup External Credentials

Follow the detailed guides in `CREDENTIALS_SETUP.md`:

- **Google OAuth**: GCP Console → create OAuth 2.0 credentials
- **Firebase**: Firebase Console → enable Cloud Messaging + download service account
- **Twilio**: Twilio Console → buy phone number + get credentials
- **AWS S3**: AWS Console → create IAM user + S3 bucket

### 2. Configure Environment

```bash
# Copy template to .env
cp .env.example .env

# Edit with your credentials
nano .env  # or your preferred editor
```

### 3. Validate Credentials

```bash
# Run validation script
bash scripts/validate-credentials.sh
```

Expected output:
```
✅ GOOGLE_CLIENT_ID is set
✅ GOOGLE_CLIENT_ID has valid format
✅ FIREBASE_SERVICE_ACCOUNT_JSON is valid JSON
✅ TWILIO_ACCOUNT_SID is set
✅ AWS_S3_BUCKET is set

✅ All required credentials are valid and configured!
```

### 4. Test Live Features

```bash
# Run end-to-end tests
node scripts/test-live-delivery.js
```

Tests validate:
- Server connectivity
- User registration & email
- Phone OTP flow
- Image upload & S3 URLs
- FCM push notifications
- Twilio SMS service

---

## 📁 File Descriptions

### CREDENTIALS_SETUP.md

**2,000+ line comprehensive guide** covering:

| Service | Sections |
|---------|----------|
| **Google OAuth** | Create GCP project, enable APIs, create credentials, setup redirect URIs, validation |
| **Firebase** | Create project, enable FCM, download service account, configure web app, Firestore setup |
| **Twilio** | Create account, buy phone number, setup webhooks, SMS configuration |
| **AWS S3** | Create IAM user, generate keys, create bucket, CORS setup, lifecycle rules |

**Includes:**
- Step-by-step screenshots links
- Environment variable names
- Validation checklists
- Test commands
- Security best practices
- Troubleshooting guide
- Local development workarounds

### scripts/validate-credentials.sh

**Automated validation script** (~400 lines)

**Features:**
- ✅ Checks all required environment variables
- ✅ Validates credential file formats (JSON parsing)
- ✅ Tests API connectivity (Google, Twilio, AWS)
- ✅ Validates credential formats (Client IDs, phone numbers, etc.)
- ✅ Generates timestamped validation report
- ✅ Color-coded output (green/red/yellow)

**Usage:**
```bash
bash scripts/validate-credentials.sh
```

**Output:**
- Real-time validation results in terminal
- Saved report: `credential-validation-report-YYYYMMDD-HHMMSS.txt`
- Exit code 0 if all tests pass, 1 if any fail

### scripts/test-live-delivery.js

**End-to-end feature test suite** (~500 lines)

**Tests:**
1. **Server Connectivity** - API health check
2. **User Registration** - Create test user, fetch profile
3. **Phone OTP** - Send and verify OTP codes
4. **Image Upload** - Request S3 presigned URLs
5. **Firebase FCM** - Test push notification connectivity
6. **Twilio SMS** - Validate phone service credentials
7. **Completeness** - Check all required env vars

**Usage:**
```bash
node scripts/test-live-delivery.js
```

**Output:**
- Test results in terminal
- JSON report: `test-delivery-report-YYYY-MM-DD.json`
- Includes pass/fail counts and error details

### .env.example

**Configuration template** (~90 lines)

Includes sections for:
- Google OAuth (Client ID, Secret, Service Account)
- Firebase (Server Key, Sender ID, API Key, Project ID)
- Twilio (Account SID, Auth Token, Phone Number)
- AWS S3 (Access Key, Secret Key, Bucket, Region)
- Development mock flags

---

## 🔧 Development Workarounds

### Use Mock Services (no external APIs)

```bash
# .env
FIREBASE_MOCK=true
AWS_MOCK=true
TWILIO_MOCK=true
```

Services will log instead of making real API calls.

### File-Based S3 Storage

```bash
# .env
AWS_MOCK=true
AWS_LOCAL_STORAGE_PATH=/tmp/sejilo-media
```

Images stored locally instead of S3.

### Email Console Output

```bash
# .env
FIREBASE_MOCK=true
FIREBASE_LOG_MESSAGES=true
```

FCM messages logged to console.

### SMS Console Output

```bash
# .env
TWILIO_MOCK=true
TWILIO_LOG_SMS=true
```

SMS messages logged to console.

---

## 🔐 Security Checklist

- [ ] Never commit `.env` to git
- [ ] Add `.env` to `.gitignore` (already done)
- [ ] Use separate credentials for dev/staging/prod
- [ ] Rotate credentials every 90 days
- [ ] Enable MFA on all cloud accounts
- [ ] Restrict IAM permissions to minimum required
- [ ] Use AWS Secrets Manager for production
- [ ] Audit credential usage regularly
- [ ] Review cloud console logs for suspicious activity

---

## ❌ Troubleshooting

### "Cannot reach API server"
- Ensure backend is running: `npm run dev` or `./run-server.sh`
- Check `SEJILO_API_BASE_URL` in `.env`
- Verify firewall allows localhost connections

### "OAuth credentials invalid"
- Verify Client ID/Secret in GCP Console
- Check redirect URIs match your app callback
- Ensure OAuth consent screen is configured
- Try regenerating credentials

### "Firebase token validation failed"
- Use Server Key (Cloud Messaging), not API key
- Verify service account JSON is readable
- Check Firebase Cloud Messaging API enabled in GCP

### "Twilio authentication failed"
- Verify Account SID and Auth Token are correct
- Check Twilio account is active
- Ensure phone number is active and SMS-capable
- Verify phone number format: `+1234567890`

### "S3 bucket access denied"
- Verify Access Key and Secret Key are correct
- Check IAM user has `AmazonS3FullAccess` policy
- Verify bucket name is correct
- Ensure region matches bucket location
- Test with: `aws s3 ls s3://$BUCKET --region $REGION`

---

## 📊 Validation Output Example

```
✅ .env file loaded
✅ GOOGLE_CLIENT_ID is set
✅ GOOGLE_CLIENT_ID has valid format
✅ No GOOGLE_CLIENT_SECRET, as expected (ID-token verification needs none)
✅ GOOGLE_SERVICE_ACCOUNT_JSON file exists and is readable
✅ GOOGLE_SERVICE_ACCOUNT_JSON is valid JSON
✅ GOOGLE_SERVICE_ACCOUNT_JSON has required fields (type, project_id)

✅ FIREBASE_SERVICE_ACCOUNT_JSON file exists and is readable
✅ FIREBASE_SERVICE_ACCOUNT_JSON is valid JSON
✅ FIREBASE_SERVICE_ACCOUNT_JSON has required fields
✅ FIREBASE_SERVER_KEY is set
✅ FIREBASE_SENDER_ID is set
✅ FIREBASE_SENDER_ID has valid format (numeric)
✅ FIREBASE_API_KEY is set
✅ FIREBASE_PROJECT_ID is set

✅ TWILIO_ACCOUNT_SID is set
✅ TWILIO_ACCOUNT_SID has valid format
✅ TWILIO_AUTH_TOKEN is set
✅ TWILIO_PHONE_NUMBER is set
✅ TWILIO_PHONE_NUMBER has valid format (E.164)
✅ Twilio API connectivity test passed

✅ AWS_ACCESS_KEY_ID is set
✅ AWS_ACCESS_KEY_ID has valid format
✅ AWS_SECRET_ACCESS_KEY is set
✅ AWS_S3_BUCKET is set
✅ AWS_S3_BUCKET has valid format
✅ AWS_REGION is set
✅ AWS_REGION is a valid AWS region
✅ AWS S3 bucket access test passed

Summary
  Passed:  28
  Failed:  0
  Skipped: 0
  Total:   28

✅ All required credentials are valid and configured!

Report saved to: credential-validation-report-20260824-162120.txt
```

---

## 📚 Reference Links

### Documentation
- [CREDENTIALS_SETUP.md](./CREDENTIALS_SETUP.md) - Full setup guides

### Cloud Services
- [Google Cloud Console](https://console.cloud.google.com)
- [Firebase Console](https://console.firebase.google.com)
- [Twilio Console](https://www.twilio.com/console)
- [AWS Console](https://console.aws.amazon.com)

### Implementation
- **Backend API**: Handles credential validation and service calls
- **Frontend**: Uses tokens and presigned URLs for uploads
- **Local Storage**: Falls back to file storage if services unavailable

---

## 🎯 Next Steps

1. **Complete setup** using `CREDENTIALS_SETUP.md`
2. **Fill in `.env`** with your credentials
3. **Run validation** with `scripts/validate-credentials.sh`
4. **Test features** with `scripts/test-live-delivery.js`
5. **Review report** and fix any issues
6. **Deploy** with confidence!

---

## 📝 Notes

- All scripts are idempotent (safe to run multiple times)
- Validation reports are timestamped and cumulative
- Tests use temporary resources (test users, test images)
- Mock modes are safe for development/testing
- Production should use real external services

---

## 🆘 Support

- **Setup issues**: See `CREDENTIALS_SETUP.md` troubleshooting section
- **Validation failures**: Check error messages from `validate-credentials.sh`
- **Test failures**: Review JSON report from `test-live-delivery.js`
- **API errors**: Check backend logs and service status dashboards
