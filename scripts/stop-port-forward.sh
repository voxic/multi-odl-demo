#!/bin/bash

# Stop Port Forwarding Script for ODL Demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print colored output with timestamps
print_status() {
    echo -e "${GREEN}[$(get_timestamp)] [INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(get_timestamp)] [ERROR]${NC} $1"
}

print_status "Stopping port forwarding processes..."

# Stop port forwarding processes
for port in 3306 8080 9092 8083 3000; do
    pid_file="/tmp/odl-port-forward-$port.pid"
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            print_status "Stopping port forwarding on port $port (PID: $pid)"
            kill $pid
            rm -f "$pid_file"
        else
            print_warning "Port forwarding on port $port was not running"
            rm -f "$pid_file"
        fi
    else
        print_warning "No PID file found for port $port"
    fi
done

# Also kill any remaining kubectl port-forward processes
print_status "Cleaning up any remaining kubectl port-forward processes..."
pkill -f "kubectl port-forward" 2>/dev/null || true

print_status "✅ All port forwarding processes stopped"
