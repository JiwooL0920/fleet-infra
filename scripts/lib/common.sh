#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
  echo -e "${BLUE}ℹ  $*${NC}"
}

success() {
  echo -e "${GREEN}✅ $*${NC}"
}

warn() {
  echo -e "${YELLOW}⚠️  $*${NC}"
}

fail() {
  echo -e "${RED}❌ $*${NC}"
}
