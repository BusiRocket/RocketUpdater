#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Bold versions
BOLD='\033[1m'
DIM='\033[2m'

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

echo_magenta() {
    echo_text "${MAGENTA}$1${NC}"
}

echo_gray() {
    echo_text "${GRAY}$1${NC}"
}

# Inline versions (no newlines)
print_red() {
    echo -e "${RED}$1${NC}"
}

print_green() {
    echo -e "${GREEN}$1${NC}"
}

print_yellow() {
    echo -e "${YELLOW}$1${NC}"
}

print_blue() {
    echo -e "${BLUE}$1${NC}"
}

print_cyan() {
    echo -e "${CYAN}$1${NC}"
}

# Utility functions
echo_separator() {
    echo -e "${GRAY}───────────────────────────────────────────${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

echo_skip() {
    echo -e "${GRAY}⏭️  $1${NC}"
}

# Progress indicator
echo_step() {
    local step=$1
    local total=$2
    local message=$3
    echo -e "${BLUE}[$step/$total]${NC} $message"
}
