#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo_text() {
    echo -e "\n$1\n"
}

# Functions for colored output
echo_red() {
    echo_text "${RED}$1${NC}"
}

echo_green() {
    echo_text "${GREEN}$1${NC}"
}

echo_yellow() {
    echo_text "${YELLOW}$1${NC}"
}

echo_blue() {
    echo_text "${BLUE}$1${NC}"
}

echo_cyan() {
    echo_text "${CYAN}$1${NC}"
}