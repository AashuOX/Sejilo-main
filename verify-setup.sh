#!/bin/bash

# SejiloChat Environment Verification Script
# Checks all prerequisites and service health

set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║      SejiloChat Environment Verification               ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ─── Check 1: Docker ───
echo "1. Checking Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo -e "   ${GREEN}✅ Docker installed: $DOCKER_VERSION${NC}"
else
    echo -e "   ${RED}❌ Docker not installed${NC}"
    exit 1
fi

if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version 2>/dev/null || docker-compose --version)
    echo -e "   ${GREEN}✅ Docker Compose: $COMPOSE_VERSION${NC}"
else
    echo -e "   ${RED}❌ Docker Compose not installed${NC}"
    exit 1
fi

# ─── Check 2: Environment File ───
echo ""
echo "2. Checking Environment Configuration..."
if [ -f ".env" ]; then
    echo -e "   ${GREEN}✅ .env file exists${NC}"

    # Check required vars
    source .env 2>/dev/null || true

    REQUIRED_VARS=("POSTGRES_PASSWORD" "REDIS_PASSWORD" "JWT_SECRET" "TOKEN_PEPPER" "METRICS_TOKEN")
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -n "${!var}" ] && [ "${!var}" != "replace-*" ] && [ "${!var}" != "CHANGE_ME*" ]; then
            echo -e "   ${GREEN}✅ $var is set${NC}"
        else
            echo -e "   ${YELLOW}⚠️  $var may need to be set${NC}"
        fi
    done
else
    echo -e "   ${RED}❌ .env file missing. Run: cp .env.example .env${NC}"
    exit 1
fi

# ─── Check 3: Project Structure ───
echo ""
echo "3. Checking Project Structure..."

DIRS=("backend" "sejilo_chat" "docs" "infra")
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "   ${GREEN}✅ $dir/ exists${NC}"
    else
        echo -e "   ${YELLOW}⚠️  $dir/ not found${NC}"
    fi
done

# ─── Check 4: Docker Services (if running) ───
echo ""
echo "4. Checking Docker Services..."

if docker-compose ps --services 2>/dev/null | grep -q "postgres\|redis\|backend"; then
    echo "   Services found in docker-compose:"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | sed 's/^/   /'

    # Check health
    echo ""
    echo "   Service Health:"
    docker-compose ps --format "{{.Name}}: {{.Status}}" 2>/dev/null | sed 's/^/   /'

    # Check backend health endpoint
    echo ""
    echo "   Testing Backend API..."
    if curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
        HEALTH=$(curl -s http://localhost:8080/health)
        echo -e "   ${GREEN}✅ Backend API healthy: $HEALTH${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Backend API not responding (may not be running)${NC}"
        echo "   Run: docker-compose up -d"
    fi
else
    echo -e "   ${YELLOW}⚠️  No docker-compose services running${NC}"
    echo "   Run: docker-compose up -d"
fi

# ─── Check 5: Node.js (for load testing) ───
echo ""
echo "5. Checking Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo -e "   ${GREEN}✅ Node.js: $NODE_VERSION${NC}"

    if command -v npm &> /dev/null; then
        NPM_VERSION=$(npm --version)
        echo -e "   ${GREEN}✅ npm: $NPM_VERSION${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠️  Node.js not installed (needed for load-test.js)${NC}"
fi

# ─── Check 6: Flutter (for mobile testing) ───
echo ""
echo "6. Checking Flutter..."
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version | head -1)
    echo -e "   ${GREEN}✅ Flutter: $FLUTTER_VERSION${NC}"
else
    echo -e "   ${YELLOW}⚠️  Flutter not in PATH (needed for mobile app)${NC}"
fi

# ─── Check 7: Backend Dependencies ───
echo ""
echo "7. Checking Backend Dependencies..."
if [ -d "backend/node_modules" ]; then
    echo -e "   ${GREEN}✅ Backend dependencies installed${NC}"
else
    echo -e "   ${YELLOW}⚠️  Backend dependencies not installed${NC}"
    echo "   Run: cd backend && npm install"
fi

# ─── Check 8: Test Files ───
echo ""
echo "8. Checking Test Files..."
TEST_FILES=("test-flows.sh" "load-test.js" "TESTING.md")
for file in "${TEST_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "   ${GREEN}✅ $file exists${NC}"
    else
        echo -e "   ${RED}❌ $file missing${NC}"
    fi
done

# ─── Summary ───
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║              Verification Complete                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Next Steps:"
echo "  1. Start services: docker-compose up -d"
echo "  2. Wait 15s for health checks: docker-compose ps"
echo "  3. Run automated tests: ./test-flows.sh"
echo "  4. Run performance tests: node load-test.js"
echo "  5. Test mobile app: cd sejilo_chat && flutter run -d emulator"
echo ""