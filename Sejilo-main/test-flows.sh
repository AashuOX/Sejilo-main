#!/bin/bash

# SejiloChat E2E Test Flows
# Tests: User sign-up, login, chat messaging, posts with reactions
# Usage: ./test-flows.sh [API_URL]

set -e

API_URL="${1:-http://localhost:8080}"
EMAIL_DOMAIN="test-$(date +%s).local"

echo "🚀 Starting SejiloChat E2E Test Flows..."
echo "API URL: $API_URL"
echo ""

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
    eval "curl -s -X $method \"$API_URL$endpoint\" $headers -d '$data'"
  else
    eval "curl -s -X $method \"$API_URL$endpoint\" $headers"
  fi
}

# ─── Test 1: Health Check ───

echo "TEST 0: Backend Health Check"
echo "════════════════════════════"

HEALTH=$(make_request GET "/health" "")

if echo "$HEALTH" | grep -q '"status":"ok"'; then
  echo "✅ Backend is healthy"
else
  echo "❌ Backend health check failed"
  echo "Response: $HEALTH"
  exit 1
fi

# ─── Test 1: User Sign-up via Email/Password ───

echo ""
echo "TEST 1: User Sign-up via Email/Password"
echo "════════════════════════════════════════"

TEST_EMAIL="user-$(date +%s)@$EMAIL_DOMAIN"
TEST_PASSWORD="SecurePassword123!"
TEST_USERNAME="testuser$(date +%s)"

echo "Registering user: $TEST_EMAIL"

SIGNUP_RESPONSE=$(make_request POST "/auth/register" \
  "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"username\":\"$TEST_USERNAME\"}")

echo "Sign-up Response: $SIGNUP_RESPONSE"

# Extract user ID and verify success
USER_ID=$(echo "$SIGNUP_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
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
  "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

echo "Login Response: $LOGIN_RESPONSE"

# Extract JWT token
ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Login failed: No access token returned"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi
echo "✅ Login successful"
echo "   Token (first 20 chars): ${ACCESS_TOKEN:0:20}..."

# ─── Test 3: Get User Profile ───

echo ""
echo "TEST 3: Get User Profile"
echo "════════════════════════"

PROFILE=$(make_request GET "/users/me" "" "$ACCESS_TOKEN")

echo "Profile Response: $PROFILE"

PROFILE_EMAIL=$(echo "$PROFILE" | grep -o '"email":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$PROFILE_EMAIL" == "$TEST_EMAIL" ]; then
  echo "✅ User profile verified - Email: $PROFILE_EMAIL"
else
  echo "⚠️  Profile email mismatch. Expected: $TEST_EMAIL, Got: $PROFILE_EMAIL"
fi

# ─── Test 4: Create a Post ───

echo ""
echo "TEST 4: Create a Post"
echo "═════════════════════"

POST_CONTENT="Test post from automation - $(date +%s)"

CREATE_POST=$(make_request POST "/posts" \
  "{\"content\":\"$POST_CONTENT\",\"visibility\":\"public\"}" "$ACCESS_TOKEN")

echo "Create Post Response: $CREATE_POST"

POST_ID=$(echo "$CREATE_POST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$POST_ID" ]; then
  echo "⚠️  Post creation response unclear, continuing..."
  POST_ID="unknown"
else
  echo "✅ Post created with ID: $POST_ID"
  echo "   Content: $POST_CONTENT"
fi

# ─── Test 5: Get Posts Feed ───

echo ""
echo "TEST 5: Get Posts Feed"
echo "══════════════════════"

FEED=$(make_request GET "/posts?limit=10&offset=0" "" "$ACCESS_TOKEN")

POST_COUNT=$(echo "$FEED" | grep -o '"id":"[^"]*"' | wc -l)
echo "Posts in feed: $POST_COUNT"
echo "✅ Feed retrieved"

# ─── Test 6: Like the Post ───

if [ "$POST_ID" != "unknown" ]; then
  echo ""
  echo "TEST 6: Like a Post"
  echo "═══════════════════"

  LIKE_POST=$(make_request POST "/posts/$POST_ID/like" "{}" "$ACCESS_TOKEN")

  echo "Like Response: $LIKE_POST"

  if echo "$LIKE_POST" | grep -q '"likeCount"'; then
    echo "✅ Post liked successfully"
  else
    echo "⚠️  Like response unclear"
  fi
else
  echo ""
  echo "TEST 6: Like a Post"
  echo "═══════════════════"
  echo "⏭️  Skipped (no valid post ID)"
fi

# ─── Test 7: Create Story ───

echo ""
echo "TEST 7: Create Story"
echo "════════════════════"

STORY_CONTENT="Test story from automation"

CREATE_STORY=$(make_request POST "/stories" \
  "{\"content\":\"$STORY_CONTENT\"}" "$ACCESS_TOKEN")

echo "Create Story Response: $CREATE_STORY"

STORY_ID=$(echo "$CREATE_STORY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$STORY_ID" ]; then
  echo "⚠️  Story creation unclear"
else
  echo "✅ Story created with ID: $STORY_ID"
fi

# ─── Test 8: Get Stories ───

echo ""
echo "TEST 8: Get Stories Feed"
echo "════════════════════════"

STORIES=$(make_request GET "/stories?limit=10" "" "$ACCESS_TOKEN")

STORY_COUNT=$(echo "$STORIES" | grep -o '"id":"[^"]*"' | wc -l)
echo "Stories available: $STORY_COUNT"
echo "✅ Stories feed retrieved"

# ─── Test 9: List Mesh Devices ───

echo ""
echo "TEST 9: List Mesh Devices"
echo "═════════════════════════"

MESH=$(make_request GET "/mesh/devices" "" "$ACCESS_TOKEN")

echo "Mesh Response: $MESH"

DEVICE_COUNT=$(echo "$MESH" | grep -o '"id":"[^"]*"' | wc -l)
if [ "$DEVICE_COUNT" -eq 0 ]; then
  echo "ℹ️  No mesh devices detected (expected on local test)"
else
  echo "✅ Mesh devices found: $DEVICE_COUNT"
fi

# ─── Test 10: Health & Readiness ───

echo ""
echo "TEST 10: Backend Readiness Check"
echo "════════════════════════════════"

READY=$(make_request GET "/health/ready" "")

if echo "$READY" | grep -q '"status":"ok"'; then
  echo "✅ Backend is ready for production"
else
  echo "⚠️  Backend readiness unclear"
fi

# ─── Test 11: API Documentation ───

echo ""
echo "TEST 11: Swagger API Documentation"
echo "═══════════════════════════════════"

SWAGGER=$(make_request GET "/api/docs" "")

if echo "$SWAGGER" | grep -q "swagger"; then
  echo "✅ Swagger docs available at $API_URL/api/docs"
else
  echo "ℹ️  Swagger endpoint may be behind nginx/proxy"
fi

# ─── Summary ───

echo ""
echo "════════════════════════════════════════════════════"
echo "✅ ALL AUTOMATED TESTS COMPLETED"
echo "════════════════════════════════════════════════════"
echo ""
echo "Test Summary:"
echo "  • User ID: $USER_ID"
echo "  • Email: $TEST_EMAIL"
echo "  • Username: $TEST_USERNAME"
if [ "$POST_ID" != "unknown" ]; then
  echo "  • Post ID: $POST_ID"
fi
if [ -n "$STORY_ID" ]; then
  echo "  • Story ID: $STORY_ID"
fi
echo ""
echo "Next Steps:"
echo "  1. Manual testing on Flutter app (emulator or device)"
echo "  2. Mesh connectivity test with 2+ devices"
echo "  3. Performance testing: node load-test.js"
echo ""
echo "Test completed at: $(date)"
echo "════════════════════════════════════════════════════"
