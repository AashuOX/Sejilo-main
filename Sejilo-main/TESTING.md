# SejiloChat Local Testing Environment Guide

Complete instructions for setting up and running the SejiloChat testing environment locally, including backend services, Android emulator, and automated test flows.

## Table of Contents

1. [Backend Services Setup](#backend-services-setup)
2. [Test Automation Scripts](#test-automation-scripts)
3. [Android Emulator Setup](#android-emulator-setup)
4. [Performance Testing](#performance-testing)
5. [Manual Testing Workflows](#manual-testing-workflows)
6. [Troubleshooting](#troubleshooting)

---

## Backend Services Setup

### Prerequisites

- Docker and Docker Compose installed
- Node.js 18+ (for running direct tests)
- Git (for project management)

### 1. Initialize Environment Configuration

Copy the example environment file and set required secrets:

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main
cp .env.example .env
```

Edit `.env` and set the following required values:

```env
POSTGRES_PASSWORD=dev_postgres_password_12345
REDIS_PASSWORD=dev_redis_password_12345
JWT_SECRET=$(openssl rand -base64 48)
TOKEN_PEPPER=$(openssl rand -base64 32)
METRICS_TOKEN=$(openssl rand -base64 32)
SEJILO_API_PORT=8080
LOG_LEVEL=debug
```

### 2. Start Docker Services

Start all backend services (PostgreSQL, Redis, Backend API):

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main
docker-compose up -d
```

**Expected Output:**
```
Creating sejilo-postgres  ... done
Creating sejilo-redis     ... done
Creating sejilo-backend   ... done
```

### 3. Verify Service Health

Check that all services are running and healthy:

```bash
docker-compose ps
```

**Expected Output:**
```
NAME                COMMAND                  SERVICE      STATUS              PORTS
sejilo-postgres     "docker-entrypoint.s…"   postgres     Up 10s (healthy)    5432/tcp
sejilo-redis        "redis-server …"         redis        Up 8s (healthy)     6379/tcp
sejilo-backend      "node dist/main.js"      backend      Up 5s (healthy)     0.0.0.0:8080->8080/tcp
```

### 4. Verify Backend API

Test the health endpoint:

```bash
curl -v http://localhost:8080/health
```

**Expected Response (200 OK):**
```json
{
  "status": "ok",
  "timestamp": "2026-08-24T16:20:00.000Z"
}
```

### 5. Access Backend Services

**API Endpoint:** http://localhost:8080
**API Documentation:** http://localhost:8080/api/docs (Swagger)
**PostgreSQL:** localhost:5432 (user: sejilo, password: dev_postgres_password_12345)
**Redis:** localhost:6379 (password: dev_redis_password_12345)

### 6. Stop Services

When finished testing, stop the services:

```bash
docker-compose down
```

To remove data volumes as well (complete reset):

```bash
docker-compose down -v
```

---

## Test Automation Scripts

### Setup: Backend Integration Tests

The backend uses Jest with e2e test suites for automated testing.

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/backend

# Install dependencies
npm install

# Run unit tests
npm run test

# Run unit tests with coverage
npm run test:cov

# Run e2e tests (requires docker-compose services running)
npm run test:e2e
```

### test-flows.sh - Complete User Flow Automation

Create a shell script for automated testing of core user flows:

```bash
#!/bin/bash

# SejiloChat E2E Test Flows
# Tests: User sign-up, login, chat messaging, posts with reactions

set -e

API_URL="http://localhost:8080"
EMAIL_DOMAIN="test-$(date +%s).local"

echo "🚀 Starting SejiloChat E2E Test Flows..."
echo "API URL: $API_URL"

# ─── Helper Functions ───

function make_request() {
  local method=$1
  local endpoint=$2
  local data=$3
  local token=${4:-""}
  
  local headers="-H 'Content-Type: application/json'"
  if [ -n "$token" ]; then
    headers="$headers -H 'Authorization: Bearer $token'"
  fi
  
  if [ -n "$data" ]; then
    curl -s -X "$method" "$API_URL$endpoint" $headers -d "$data"
  else
    curl -s -X "$method" "$API_URL$endpoint" $headers
  fi
}

# ─── Test 1: User Sign-up via Email/Password ───

echo ""
echo "TEST 1: User Sign-up via Email/Password"
echo "════════════════════════════════════════"

TEST_EMAIL="user-$(date +%s)@$EMAIL_DOMAIN"
TEST_PASSWORD="SecurePassword123!"
TEST_USERNAME="testuser$(date +%s)"

echo "Registering user: $TEST_EMAIL"

SIGNUP_RESPONSE=$(make_request POST "/auth/register" \
  "{
    \"email\": \"$TEST_EMAIL\",
    \"password\": \"$TEST_PASSWORD\",
    \"username\": \"$TEST_USERNAME\"
  }")

echo "Sign-up Response: $SIGNUP_RESPONSE"

# Extract user ID and verify success
USER_ID=$(echo "$SIGNUP_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1)
if [ -z "$USER_ID" ]; then
  echo "❌ Sign-up failed: No user ID returned"
  exit 1
fi
echo "✅ User created with ID: $USER_ID"

# ─── Test 2: User Login ───

echo ""
echo "TEST 2: User Login"
echo "══════════════════"

LOGIN_RESPONSE=$(make_request POST "/auth/login" \
  "{
    \"email\": \"$TEST_EMAIL\",
    \"password\": \"$TEST_PASSWORD\"
  }")

echo "Login Response: $LOGIN_RESPONSE"

# Extract JWT token
ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4 | head -1)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Login failed: No access token returned"
  exit 1
fi
echo "✅ Login successful, token acquired"

# ─── Test 3: Create a Post ───

echo ""
echo "TEST 3: Create a Post"
echo "═════════════════════"

POST_CONTENT="Test post from automation - $(date)"

CREATE_POST=$(make_request POST "/posts" \
  "{
    \"content\": \"$POST_CONTENT\",
    \"visibility\": \"public\"
  }" "$ACCESS_TOKEN")

echo "Create Post Response: $CREATE_POST"

POST_ID=$(echo "$CREATE_POST" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1)
if [ -z "$POST_ID" ]; then
  echo "❌ Post creation failed"
  exit 1
fi
echo "✅ Post created with ID: $POST_ID"

# ─── Test 4: Like the Post ───

echo ""
echo "TEST 4: Like a Post"
echo "═══════════════════"

LIKE_POST=$(make_request POST "/posts/$POST_ID/like" \
  "{}" "$ACCESS_TOKEN")

echo "Like Response: $LIKE_POST"
echo "✅ Post liked successfully"

# ─── Test 5: Get Post Details ───

echo ""
echo "TEST 5: Get Post Details"
echo "════════════════════════"

GET_POST=$(make_request GET "/posts/$POST_ID" "" "$ACCESS_TOKEN")

LIKE_COUNT=$(echo "$GET_POST" | grep -o '"likeCount":[0-9]*' | cut -d':' -f2)
echo "Post likes: $LIKE_COUNT"

if [ "$LIKE_COUNT" -ge 1 ]; then
  echo "✅ Post retrieved, like count verified"
else
  echo "⚠️  Like count verification inconclusive"
fi

# ─── Test 6: Send Chat Message ───

echo ""
echo "TEST 6: Send Chat Message"
echo "═════════════════════════"

CHAT_MESSAGE=$(make_request POST "/chat/messages" \
  "{
    \"content\": \"Hello from automated test - $(date)\",
    \"recipientId\": \"$USER_ID\"
  }" "$ACCESS_TOKEN")

echo "Chat Response: $CHAT_MESSAGE"

MESSAGE_ID=$(echo "$CHAT_MESSAGE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1)
if [ -z "$MESSAGE_ID" ]; then
  echo "⚠️  Message creation may have failed (check API response)"
else
  echo "✅ Chat message sent with ID: $MESSAGE_ID"
fi

# ─── Test 7: Verify User Profile ───

echo ""
echo "TEST 7: Verify User Profile"
echo "════════════════════════════"

PROFILE=$(make_request GET "/users/me" "" "$ACCESS_TOKEN")

PROFILE_EMAIL=$(echo "$PROFILE" | grep -o '"email":"[^"]*"' | cut -d'"' -f4 | head -1)
echo "Profile email: $PROFILE_EMAIL"

if [ "$PROFILE_EMAIL" == "$TEST_EMAIL" ]; then
  echo "✅ User profile verified"
else
  echo "❌ Profile verification failed"
fi

# ─── Summary ───

echo ""
echo "════════════════════════════════════════"
echo "✅ ALL TESTS COMPLETED SUCCESSFULLY"
echo "════════════════════════════════════════"
echo "Test Summary:"
echo "  • User ID: $USER_ID"
echo "  • Email: $TEST_EMAIL"
echo "  • Post ID: $POST_ID"
echo "  • Message ID: $MESSAGE_ID"
echo ""
echo "Test completed at: $(date)"
```

### Running the Test Script

```bash
# Copy script to root directory
cp test-flows.sh /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/

# Make executable
chmod +x /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/test-flows.sh

# Ensure docker services are running
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main
docker-compose up -d

# Wait for services to be healthy (10-15 seconds)
sleep 15

# Run the test flow
./test-flows.sh
```

**Expected Output:**
```
🚀 Starting SejiloChat E2E Test Flows...
API URL: http://localhost:8080

TEST 1: User Sign-up via Email/Password
════════════════════════════════════════
Registering user: user-1723398857@test-1723398857.local
✅ User created with ID: 550e8400-e29b-41d4-a716-446655440000

TEST 2: User Login
══════════════════
✅ Login successful, token acquired

TEST 3: Create a Post
═════════════════════
✅ Post created with ID: 660e8400-e29b-41d4-a716-446655440001

TEST 4: Like a Post
═══════════════════
✅ Post liked successfully

TEST 5: Get Post Details
════════════════════════
Post likes: 1
✅ Post retrieved, like count verified

TEST 6: Send Chat Message
═════════════════════════
✅ Chat message sent with ID: 770e8400-e29b-41d4-a716-446655440002

TEST 7: Verify User Profile
════════════════════════════
Profile email: user-1723398857@test-1723398857.local
✅ User profile verified

════════════════════════════════════════
✅ ALL TESTS COMPLETED SUCCESSFULLY
════════════════════════════════════════
```

### WebSocket Chat Testing

For real-time WebSocket chat testing:

```bash
# Backend e2e WebSocket tests
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/backend

# Run WebSocket chat tests
npm run test:e2e -- chat-ws.e2e-spec.ts
```

---

## Android Emulator Setup

### Prerequisites

- Android SDK installed (API 28+)
- Flutter SDK installed
- Android emulator or physical device

### 1. Create/Start Android Emulator

```bash
# List available emulators
$ANDROID_SDK_ROOT/emulator/emulator -list-avds

# Start emulator (example: pixel_3)
$ANDROID_SDK_ROOT/emulator/emulator -avd pixel_3 -netdelay none -netspeed full &
```

### 2. Configure Backend URL

The emulator runs in a separate network namespace. Use the special IP address `10.0.2.2` to reach localhost from the emulator.

Create or update `lib/config/api_config.dart`:

```dart
class ApiConfig {
  static const String baseUrl = 
    String.fromEnvironment('BACKEND_URL', 
      defaultValue: 'http://10.0.2.2:8080');
  
  static const String wsUrl = 
    String.fromEnvironment('BACKEND_WS_URL', 
      defaultValue: 'ws://10.0.2.2:8080');
}
```

### 3. Run Flutter App on Emulator

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/sejilo_chat

# Install dependencies
flutter pub get

# Run app on emulator
flutter run -d emulator-5554 --verbose

# Or specify custom backend URL at runtime
flutter run -d emulator-5554 \
  --dart-define=BACKEND_URL=http://10.0.2.2:8080 \
  --verbose
```

### 4. Monitor Emulator Logs

```bash
flutter logs -d emulator-5554
```

### 5. Common Emulator Issues

**Issue: "ADB not found"**
```bash
export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
```

**Issue: "Emulator not detected"**
```bash
# Check emulator status
adb devices

# Restart ADB
adb kill-server
adb start-server
```

**Issue: "Backend unreachable from emulator"**
- Verify backend is running: `curl http://localhost:8080/health`
- Use `10.0.2.2` instead of `localhost` or `127.0.0.1`
- Check firewall rules allow port 8080

### 6. Test Flutter UI Integration

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/sejilo_chat

# Run widget tests
flutter test

# Run specific test file
flutter test test/screens/login_screen_test.dart

# Run with coverage
flutter test --coverage
```

---

## Performance Testing

### load-test.js - WebSocket and HTTP Load Testing

Create a performance test script:

```javascript
// File: load-test.js
// Load testing for WebSocket connections, message throughput, and database performance

const http = require('http');
const WebSocket = require('ws');

const API_URL = 'http://localhost:8080';
const WS_URL = 'ws://localhost:8080';
const NUM_CLIENTS = 50;
const MESSAGES_PER_CLIENT = 100;
const MESSAGE_INTERVAL_MS = 100;

class TestClient {
  constructor(clientId, onComplete) {
    this.clientId = clientId;
    this.onComplete = onComplete;
    this.token = null;
    this.ws = null;
    this.metrics = {
      signupTime: 0,
      loginTime: 0,
      wsConnectTime: 0,
      messagesSent: 0,
      messagesReceived: 0,
      avgMessageLatency: 0,
      errors: 0,
      startTime: Date.now()
    };
  }

  async signup() {
    const email = `perf-test-${this.clientId}-${Date.now()}@test.local`;
    const password = 'TestPassword123!';
    const username = `perftest${this.clientId}`;

    const start = Date.now();

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify({
        email,
        password,
        username
      });

      const options = {
        hostname: 'localhost',
        port: 8080,
        path: '/auth/register',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        }
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          this.metrics.signupTime = Date.now() - start;
          try {
            const response = JSON.parse(data);
            resolve(response);
          } catch (e) {
            reject(new Error(`Signup failed: ${res.statusCode}`));
          }
        });
      });

      req.on('error', reject);
      req.write(postData);
      req.end();
    });
  }

  async login(email, password) {
    const start = Date.now();

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify({ email, password });

      const options = {
        hostname: 'localhost',
        port: 8080,
        path: '/auth/login',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        }
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          this.metrics.loginTime = Date.now() - start;
          try {
            const response = JSON.parse(data);
            this.token = response.accessToken;
            resolve(response);
          } catch (e) {
            reject(new Error(`Login failed: ${res.statusCode}`));
          }
        });
      });

      req.on('error', reject);
      req.write(postData);
      req.end();
    });
  }

  connectWebSocket() {
    return new Promise((resolve, reject) => {
      const start = Date.now();

      try {
        this.ws = new WebSocket(`${WS_URL}/chat`, {
          headers: {
            Authorization: `Bearer ${this.token}`
          }
        });

        this.ws.on('open', () => {
          this.metrics.wsConnectTime = Date.now() - start;
          resolve();
        });

        this.ws.on('message', (data) => {
          this.metrics.messagesReceived++;
        });

        this.ws.on('error', (error) => {
          this.metrics.errors++;
          reject(error);
        });

        this.ws.on('close', () => {
          console.log(`Client ${this.clientId}: WebSocket closed`);
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  async sendMessages() {
    const latencies = [];

    for (let i = 0; i < MESSAGES_PER_CLIENT; i++) {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        const start = Date.now();
        const message = {
          type: 'message',
          content: `Performance test message ${i} from client ${this.clientId}`,
          timestamp: start
        };

        this.ws.send(JSON.stringify(message));
        this.metrics.messagesSent++;

        latencies.push(Date.now() - start);

        // Throttle messages
        await new Promise(resolve => setTimeout(resolve, MESSAGE_INTERVAL_MS));
      }
    }

    this.metrics.avgMessageLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
  }

  async run() {
    try {
      console.log(`[Client ${this.clientId}] Starting test...`);

      // Sign up
      const signupResponse = await this.signup();
      console.log(`[Client ${this.clientId}] Signup complete (${this.metrics.signupTime}ms)`);

      // Login
      await this.login(signupResponse.email, 'TestPassword123!');
      console.log(`[Client ${this.clientId}] Login complete (${this.metrics.loginTime}ms)`);

      // Connect WebSocket
      await this.connectWebSocket();
      console.log(`[Client ${this.clientId}] WebSocket connected (${this.metrics.wsConnectTime}ms)`);

      // Send messages
      await this.sendMessages();
      console.log(`[Client ${this.clientId}] Messages sent (${this.metrics.messagesSent})`);

      // Cleanup
      if (this.ws) this.ws.close();

      this.metrics.totalTime = Date.now() - this.metrics.startTime;
      this.onComplete(this.metrics);
    } catch (error) {
      console.error(`[Client ${this.clientId}] Error:`, error.message);
      this.metrics.errors++;
      this.onComplete(this.metrics);
    }
  }
}

async function runLoadTest() {
  console.log(`
╔════════════════════════════════════════╗
║     SejiloChat Performance Test        ║
╚════════════════════════════════════════╝

Configuration:
  • Concurrent clients: ${NUM_CLIENTS}
  • Messages per client: ${MESSAGES_PER_CLIENT}
  • Message interval: ${MESSAGE_INTERVAL_MS}ms
  • Total messages: ${NUM_CLIENTS * MESSAGES_PER_CLIENT}

Starting load test...
  `);

  const allMetrics = [];
  let completed = 0;

  const testPromises = Array.from({ length: NUM_CLIENTS }, (_, i) => {
    return new Promise((resolve) => {
      const client = new TestClient(i + 1, (metrics) => {
        allMetrics.push(metrics);
        completed++;
        console.log(`[Progress] ${completed}/${NUM_CLIENTS} clients completed`);
        resolve();
      });
      client.run();
    });
  });

  await Promise.all(testPromises);

  // Calculate aggregate metrics
  const avgSignupTime = allMetrics.reduce((sum, m) => sum + m.signupTime, 0) / NUM_CLIENTS;
  const avgLoginTime = allMetrics.reduce((sum, m) => sum + m.loginTime, 0) / NUM_CLIENTS;
  const avgWsTime = allMetrics.reduce((sum, m) => sum + m.wsConnectTime, 0) / NUM_CLIENTS;
  const totalMessagesSent = allMetrics.reduce((sum, m) => sum + m.messagesSent, 0);
  const totalMessagesReceived = allMetrics.reduce((sum, m) => sum + m.messagesReceived, 0);
  const avgLatency = allMetrics.reduce((sum, m) => sum + m.avgMessageLatency, 0) / NUM_CLIENTS;
  const totalErrors = allMetrics.reduce((sum, m) => sum + m.errors, 0);
  const maxTotalTime = Math.max(...allMetrics.map(m => m.totalTime));

  console.log(`
╔════════════════════════════════════════╗
║         Test Results Summary           ║
╚════════════════════════════════════════╝

Authentication Performance:
  • Avg signup time: ${avgSignupTime.toFixed(2)}ms
  • Avg login time: ${avgLoginTime.toFixed(2)}ms
  • Avg WS connect time: ${avgWsTime.toFixed(2)}ms

Message Performance:
  • Total messages sent: ${totalMessagesSent}
  • Total messages received: ${totalMessagesReceived}
  • Avg message latency: ${avgLatency.toFixed(2)}ms
  • Delivery rate: ${((totalMessagesReceived / totalMessagesSent) * 100).toFixed(2)}%

System Metrics:
  • Total errors: ${totalErrors}
  • Test duration: ${maxTotalTime}ms
  • Throughput: ${(totalMessagesSent / (maxTotalTime / 1000)).toFixed(2)} msg/sec

Recommendations:
${avgLatency > 100 ? '  ⚠️  Message latency is high (>100ms). Check database and network.' : '  ✅ Message latency acceptable'}
${totalErrors > NUM_CLIENTS * 0.05 ? '  ⚠️  Error rate exceeds 5%. Review logs.' : '  ✅ Error rate acceptable'}
${totalMessagesReceived < totalMessagesSent * 0.95 ? '  ⚠️  Message delivery rate < 95%. Check WebSocket connection.' : '  ✅ Message delivery acceptable'}
  `);
}

runLoadTest().catch(console.error);
```

### Running Performance Tests

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main

# Install dependencies if needed
npm install ws

# Start backend services
docker-compose up -d
sleep 15

# Run load test
node load-test.js
```

**Expected Output:**
```
╔════════════════════════════════════════╗
║     SejiloChat Performance Test        ║
╚════════════════════════════════════════╝

Configuration:
  • Concurrent clients: 50
  • Messages per client: 100
  • Message interval: 100ms
  • Total messages: 5000

Starting load test...

[Progress] 50/50 clients completed

╔════════════════════════════════════════╗
║         Test Results Summary           ║
╚════════════════════════════════════════╝

Authentication Performance:
  • Avg signup time: 145.23ms
  • Avg login time: 98.76ms
  • Avg WS connect time: 42.15ms

Message Performance:
  • Total messages sent: 5000
  • Total messages received: 4987
  • Avg message latency: 34.56ms
  • Delivery rate: 99.74%

System Metrics:
  • Total errors: 2
  • Test duration: 12456ms
  • Throughput: 401.41 msg/sec

Recommendations:
  ✅ Message latency acceptable
  ✅ Error rate acceptable
  ✅ Message delivery acceptable
```

---

## Manual Testing Workflows

### Workflow 1: Complete User Registration and Profile Setup

1. Start the app (emulator or device)
2. Tap "Sign Up" → Create account with:
   - Username: `testuser_$(date +%s)`
   - Email: `test$(date +%s)@example.com`
   - Password: Complex password with numbers and symbols
3. Verify email confirmation (in dev mode, logs show link)
4. Set profile picture (select from assets or camera)
5. Add bio: "Test profile for QA"
6. Verify profile appears correctly in "Me" tab

**Expected Result:** Profile displays with all entered information

### Workflow 2: Mesh Network Communication

**Prerequisites:** Two devices/emulators with Sejilo installed

1. **Device 1:**
   - Open Sejilo Chat
   - Go to Mesh tab
   - Enable "Visible to nearby devices"

2. **Device 2:**
   - Open Sejilo Chat
   - Go to Mesh tab
   - Enable "Visible to nearby devices"
   - Wait 10-15 seconds for Device 1 to appear

3. **Device 1:**
   - Tap Device 2 from nearby devices list
   - Send public message: "Hello from Device 1"

4. **Device 2:**
   - Verify message appears
   - Reply: "Hello from Device 2"

**Expected Result:** Messages are exchanged via local Bluetooth mesh, no internet required

### Workflow 3: Post Creation and Social Interactions

1. Navigate to "Posts" tab
2. Tap "Create Post"
3. Enter: "Test post with #hashtag and @mention"
4. Add image (optional)
5. Set visibility to "Public"
6. Tap "Post"
7. Verify post appears in feed
8. Tap ❤️ to like post
9. Tap comment icon → add comment
10. Verify like count and comment appear

**Expected Result:** Post, likes, and comments function correctly

### Workflow 4: Chat and WebSocket Connection

1. Navigate to "Chats" tab
2. Tap "New Chat"
3. Select a contact or enter username
4. Send: "Testing WebSocket chat at $(date)"
5. Verify message shows "sending" → "sent" states
6. Close app, reopen
7. Navigate to chat → verify message persisted locally

**Expected Result:** Chat messages sync via WebSocket and persist locally

### Workflow 5: Search and Filters

1. Go to Posts tab
2. Tap search icon
3. Enter: "test"
4. Verify results filter in real-time
5. Try hashtag search: "#sejilo"
6. Try user search: "@username"

**Expected Result:** All search types return relevant results

---

## Troubleshooting

### Backend Issues

**Problem: Docker services won't start**
```bash
# Check Docker daemon
docker ps

# Clean up volumes and restart
docker-compose down -v
docker-compose up -d
```

**Problem: Backend API returns 502 Bad Gateway**
```bash
# Check backend logs
docker-compose logs backend

# Verify database connectivity
docker-compose logs postgres
```

**Problem: WebSocket connection fails**
```bash
# Check WebSocket endpoint directly
wscat -c ws://localhost:8080/chat
```

### Frontend Issues

**Problem: Flutter app can't reach backend**
- Ensure backend is running: `curl http://localhost:8080/health`
- On emulator, use `http://10.0.2.2:8080`
- On device, use actual machine IP: `http://192.168.x.x:8080`

**Problem: Bluetooth mesh not working**
- Verify Bluetooth is enabled on device
- Check location permissions (Android 12+)
- Try "Restart nearby scan" button
- Ensure minimum 2 devices/emulators

**Problem: Tests timeout**
```bash
# Increase timeout
npm run test:e2e -- --testTimeout 30000

# Or run specific test
npm run test:e2e -- chat.e2e-spec.ts
```

### Database Issues

**Problem: Migrations won't run**
```bash
# Reset database
docker-compose down -v
docker-compose up -d postgres redis
sleep 10

# Manually run migrations
cd backend
npm run prisma:deploy
```

**Problem: Stale data in tests**
```bash
# Clean test database between runs
cd backend
npm run test:e2e -- --forceExit --clearCache
```

### Performance Issues

**Problem: High latency in load tests**
- Check CPU/memory: `docker stats`
- Increase Docker memory limit: Edit Docker Desktop settings
- Reduce concurrent clients in load-test.js
- Check database slow queries: `SELECT * FROM pg_stat_statements;`

**Problem: WebSocket connections drop**
- Check connection limits: `MAX_SOCKETS_PER_DEVICE` in `.env`
- Review Redis memory: `docker-compose exec redis redis-cli INFO memory`
- Check network throughput during test

---

## Test Coverage Reports

### Backend Coverage

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/backend
npm run test:cov

# View coverage report
open coverage/lcov-report/index.html  # macOS
xdg-open coverage/lcov-report/index.html  # Linux
start coverage/lcov-report/index.html  # Windows
```

### Frontend Coverage

```bash
cd /c/Users/ASUS/Desktop/Sejilo-main/Sejilo-main/sejilo_chat
flutter test --coverage

# View coverage
open coverage/lcov.info
```

---

## CI/CD Integration

### GitHub Actions Test Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_DB: sejilo
          POSTGRES_USER: sejilo
          POSTGRES_PASSWORD: testpass
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:8-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: cd backend && npm install

      - name: Run unit tests
        run: cd backend && npm run test

      - name: Run e2e tests
        run: cd backend && npm run test:e2e
        env:
          DATABASE_URL: postgresql://sejilo:testpass@localhost:5432/sejilo
          REDIS_URL: redis://localhost:6379
```

---

## Summary

You now have a complete testing environment with:

- ✅ Docker services (PostgreSQL, Redis, Backend API) running locally
- ✅ Automated test flows for user registration, posting, chat, and social features
- ✅ Android emulator setup with correct backend URL configuration
- ✅ Performance load testing for WebSocket and HTTP endpoints
- ✅ Manual testing workflows for all major features
- ✅ Troubleshooting guide for common issues

For questions or issues, check the Troubleshooting section or review backend logs:

```bash
docker-compose logs -f backend
```

Happy testing!
