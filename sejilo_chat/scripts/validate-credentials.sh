#!/bin/bash

################################################################################
# SejiloChat Credential Validation Script
#
# Validates all external service credentials and reports their status.
# Run this after setting up credentials in .env
#
# Usage: bash scripts/validate-credentials.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Report array
declare -a REPORT=()

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_pass() {
    echo -e "${GREEN}✅${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    REPORT+=("✅ $1")
}

log_fail() {
    echo -e "${RED}❌${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    REPORT+=("❌ $1")
}

log_skip() {
    echo -e "${YELLOW}⊘${NC}  $1 (skipped)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    REPORT+=("⊘  $1")
}

log_warn() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

separator() {
    echo ""
    echo -e "${BLUE}─────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Load .env file if it exists
load_env() {
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
        return 0
    else
        return 1
    fi
}

# Check if variable is set and not empty
check_var() {
    local var_name="$1"
    local var_value="${!var_name}"

    if [ -z "$var_value" ]; then
        return 1
    fi
    return 0
}

# Check if file exists and is readable
check_file() {
    local file_path="$1"

    # Expand ~ if present
    file_path="${file_path/#\~/$HOME}"

    if [ -f "$file_path" ] && [ -r "$file_path" ]; then
        return 0
    fi
    return 1
}

# Validate JSON file
validate_json() {
    local file_path="$1"

    # Expand ~ if present
    file_path="${file_path/#\~/$HOME}"

    if ! [ -f "$file_path" ]; then
        return 1
    fi

    if command -v jq &> /dev/null; then
        if jq empty "$file_path" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        # Fallback: try to parse with Python or grep
        if python3 -c "import json; json.load(open('$file_path'))" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

################################################################################
# Validation Tests
################################################################################

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SejiloChat Credential Validation Report              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load .env
log_info "Loading configuration from .env file..."
if load_env; then
    log_pass ".env file loaded"
else
    log_warn ".env file not found, checking environment variables only"
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# Google OAuth Validation
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}Google OAuth${NC}"

if check_var "GOOGLE_CLIENT_ID"; then
    log_pass "GOOGLE_CLIENT_ID is set"

    # Validate format
    if [[ "$GOOGLE_CLIENT_ID" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
        log_pass "GOOGLE_CLIENT_ID has valid format"
    else
        log_warn "GOOGLE_CLIENT_ID format looks unusual (expected: ***-***.apps.googleusercontent.com)"
    fi
else
    log_skip "GOOGLE_CLIENT_ID"
fi

if check_var "GOOGLE_CLIENT_SECRET"; then
    # Not a pass. This backend verifies a Google ID token's signature and
    # audience; it never exchanges an authorization code, so nothing reads a
    # client secret. One that is set here is a credential stored for nothing.
    log_warn "GOOGLE_CLIENT_SECRET is set but unused — remove it, and rotate it in the Google console"
else
    log_pass "No GOOGLE_CLIENT_SECRET, as expected (ID-token verification needs none)"
fi

if check_var "GOOGLE_SERVICE_ACCOUNT_JSON"; then
    if check_file "$GOOGLE_SERVICE_ACCOUNT_JSON"; then
        log_pass "GOOGLE_SERVICE_ACCOUNT_JSON file exists and is readable"

        if validate_json "$GOOGLE_SERVICE_ACCOUNT_JSON"; then
            log_pass "GOOGLE_SERVICE_ACCOUNT_JSON is valid JSON"

            # Check required fields
            expanded_path="${GOOGLE_SERVICE_ACCOUNT_JSON/#\~/$HOME}"
            if command -v jq &> /dev/null; then
                if jq -e '.type == "service_account" and .project_id' "$expanded_path" >/dev/null 2>&1; then
                    log_pass "GOOGLE_SERVICE_ACCOUNT_JSON has required fields (type, project_id)"
                else
                    log_fail "GOOGLE_SERVICE_ACCOUNT_JSON missing required fields"
                fi
            fi
        else
            log_fail "GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON"
        fi
    else
        log_fail "GOOGLE_SERVICE_ACCOUNT_JSON file not found or not readable"
    fi
else
    log_skip "GOOGLE_SERVICE_ACCOUNT_JSON"
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# Firebase Validation
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}Firebase Cloud Messaging${NC}"

if check_var "FIREBASE_SERVICE_ACCOUNT_JSON"; then
    if check_file "$FIREBASE_SERVICE_ACCOUNT_JSON"; then
        log_pass "FIREBASE_SERVICE_ACCOUNT_JSON file exists and is readable"

        if validate_json "$FIREBASE_SERVICE_ACCOUNT_JSON"; then
            log_pass "FIREBASE_SERVICE_ACCOUNT_JSON is valid JSON"

            # Check required fields for Firebase
            expanded_path="${FIREBASE_SERVICE_ACCOUNT_JSON/#\~/$HOME}"
            if command -v jq &> /dev/null; then
                if jq -e '.type == "service_account" and .project_id' "$expanded_path" >/dev/null 2>&1; then
                    log_pass "FIREBASE_SERVICE_ACCOUNT_JSON has required fields"
                else
                    log_fail "FIREBASE_SERVICE_ACCOUNT_JSON missing required fields"
                fi
            fi
        else
            log_fail "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON"
        fi
    else
        log_fail "FIREBASE_SERVICE_ACCOUNT_JSON file not found or not readable"
    fi
else
    log_skip "FIREBASE_SERVICE_ACCOUNT_JSON"
fi

if check_var "FIREBASE_SERVER_KEY"; then
    log_pass "FIREBASE_SERVER_KEY is set"
    log_warn "This is a server secret - keep it safe"
else
    log_skip "FIREBASE_SERVER_KEY"
fi

if check_var "FIREBASE_SENDER_ID"; then
    log_pass "FIREBASE_SENDER_ID is set"

    # Validate format (should be numeric)
    if [[ "$FIREBASE_SENDER_ID" =~ ^[0-9]+$ ]]; then
        log_pass "FIREBASE_SENDER_ID has valid format (numeric)"
    else
        log_warn "FIREBASE_SENDER_ID should be numeric"
    fi
else
    log_skip "FIREBASE_SENDER_ID"
fi

if check_var "FIREBASE_API_KEY"; then
    log_pass "FIREBASE_API_KEY is set"
else
    log_skip "FIREBASE_API_KEY"
fi

if check_var "FIREBASE_PROJECT_ID"; then
    log_pass "FIREBASE_PROJECT_ID is set"
else
    log_skip "FIREBASE_PROJECT_ID"
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# Twilio Validation
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}Twilio SMS Service${NC}"

if check_var "TWILIO_ACCOUNT_SID"; then
    log_pass "TWILIO_ACCOUNT_SID is set"

    # Validate format (should start with AC)
    if [[ "$TWILIO_ACCOUNT_SID" =~ ^AC[a-f0-9]{32}$ ]]; then
        log_pass "TWILIO_ACCOUNT_SID has valid format"
    else
        log_warn "TWILIO_ACCOUNT_SID format looks unusual (expected: AC + 32 hex chars)"
    fi
else
    log_skip "TWILIO_ACCOUNT_SID"
fi

if check_var "TWILIO_AUTH_TOKEN"; then
    log_pass "TWILIO_AUTH_TOKEN is set"
    log_warn "This is a secret token - keep it safe"
else
    log_skip "TWILIO_AUTH_TOKEN"
fi

if check_var "TWILIO_PHONE_NUMBER"; then
    log_pass "TWILIO_PHONE_NUMBER is set"

    # Validate format
    if [[ "$TWILIO_PHONE_NUMBER" =~ ^\+?[0-9]{10,15}$ ]]; then
        log_pass "TWILIO_PHONE_NUMBER has valid format (E.164)"
    else
        log_warn "TWILIO_PHONE_NUMBER format should be E.164 (+1234567890)"
    fi
else
    log_skip "TWILIO_PHONE_NUMBER"
fi

# Test Twilio connectivity if credentials are available
if check_var "TWILIO_ACCOUNT_SID" && check_var "TWILIO_AUTH_TOKEN"; then
    log_info "Testing Twilio API connectivity..."

    if command -v curl &> /dev/null; then
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
            "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID")

        if [ "$response" = "200" ]; then
            log_pass "Twilio API connectivity test passed"
        else
            log_fail "Twilio API connectivity test failed (HTTP $response)"
        fi
    else
        log_warn "curl not available, skipping Twilio connectivity test"
    fi
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# AWS S3 Validation
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}AWS S3 Storage${NC}"

if check_var "AWS_ACCESS_KEY_ID"; then
    log_pass "AWS_ACCESS_KEY_ID is set"

    # Validate format (should start with AKIA)
    if [[ "$AWS_ACCESS_KEY_ID" =~ ^AKIA[0-9A-Z]{16}$ ]]; then
        log_pass "AWS_ACCESS_KEY_ID has valid format"
    else
        log_warn "AWS_ACCESS_KEY_ID format looks unusual (expected: AKIA + 16 chars)"
    fi
else
    log_skip "AWS_ACCESS_KEY_ID"
fi

if check_var "AWS_SECRET_ACCESS_KEY"; then
    log_pass "AWS_SECRET_ACCESS_KEY is set"
    log_warn "This is a secret key - keep it safe"
else
    log_skip "AWS_SECRET_ACCESS_KEY"
fi

if check_var "AWS_S3_BUCKET"; then
    log_pass "AWS_S3_BUCKET is set"

    # Validate bucket name format
    if [[ "$AWS_S3_BUCKET" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] && [ ${#AWS_S3_BUCKET} -le 63 ]; then
        log_pass "AWS_S3_BUCKET has valid format"
    else
        log_warn "AWS_S3_BUCKET format looks unusual (lowercase alphanumeric, -, . only)"
    fi
else
    log_skip "AWS_S3_BUCKET"
fi

if check_var "AWS_REGION"; then
    log_pass "AWS_REGION is set"

    # Validate common AWS regions
    valid_regions="us-east-1|us-west-2|eu-west-1|ap-southeast-1|ap-northeast-1"
    if [[ "$AWS_REGION" =~ ^(us-east-1|us-west-1|us-west-2|eu-west-1|eu-central-1|ap-southeast-1|ap-northeast-1|ap-south-1)$ ]]; then
        log_pass "AWS_REGION is a valid AWS region"
    else
        log_warn "AWS_REGION '$AWS_REGION' is unusual (check against AWS region list)"
    fi
else
    log_skip "AWS_REGION"
fi

# Test AWS S3 connectivity if credentials are available
if check_var "AWS_ACCESS_KEY_ID" && check_var "AWS_SECRET_ACCESS_KEY" && check_var "AWS_S3_BUCKET"; then
    log_info "Testing AWS S3 bucket access..."

    if command -v aws &> /dev/null; then
        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION

        if aws s3 ls "s3://$AWS_S3_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
            log_pass "AWS S3 bucket access test passed"
        else
            log_fail "AWS S3 bucket access test failed (check permissions or bucket name)"
        fi
    else
        log_warn "AWS CLI not available, skipping S3 connectivity test"
        log_info "Install AWS CLI to enable connectivity tests: pip install awscli"
    fi
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# Development Workarounds
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}Development Mode Settings${NC}"

if check_var "FIREBASE_MOCK"; then
    log_pass "Firebase mock mode enabled (development only)"
else
    log_info "Firebase mock mode not set"
fi

if check_var "AWS_MOCK"; then
    log_pass "AWS S3 mock mode enabled (development only)"
else
    log_info "AWS S3 mock mode not set"
fi

if check_var "TWILIO_MOCK"; then
    log_pass "Twilio mock mode enabled (development only)"
else
    log_info "Twilio mock mode not set"
fi

separator

# ─────────────────────────────────────────────────────────────────────────────
# Summary Report
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${BLUE}Summary${NC}"
echo ""

total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

echo "Tests passed:  ${GREEN}${TESTS_PASSED}${NC}"
echo "Tests failed:  ${RED}${TESTS_FAILED}${NC}"
echo "Tests skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
echo "Total tests:   $total_tests"
echo ""

# Overall status
if [ $TESTS_FAILED -eq 0 ]; then
    if [ $TESTS_PASSED -gt 0 ]; then
        echo -e "${GREEN}✅ All required credentials are valid and configured!${NC}"
        status_code=0
    else
        echo -e "${YELLOW}⚠  No credentials configured (running in offline mode)${NC}"
        status_code=1
    fi
else
    echo -e "${RED}❌ Some credentials are missing or invalid. See details above.${NC}"
    status_code=1
fi

echo ""
echo -e "${BLUE}Detailed Report:${NC}"
for item in "${REPORT[@]}"; do
    echo "  $item"
done

echo ""
echo -e "${BLUE}─────────────────────────────────────────────────────────${NC}"
echo ""

# Save report to file
REPORT_FILE="credential-validation-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "SejiloChat Credential Validation Report"
    echo "Generated: $(date)"
    echo ""
    echo "Summary:"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"
    echo "  Skipped: $TESTS_SKIPPED"
    echo ""
    echo "Details:"
    for item in "${REPORT[@]}"; do
        echo "  $item"
    done
} > "$REPORT_FILE"

log_info "Report saved to: $REPORT_FILE"

exit $status_code
