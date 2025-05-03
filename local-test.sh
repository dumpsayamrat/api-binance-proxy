#!/bin/bash
# Local test script for the Binance API Proxy Lambda

echo "=============================================="
echo "   Binance API Proxy - Local Testing Tool    "
echo "=============================================="
echo ""

# Build the Rust project
echo "Building the Lambda function..."
cargo build

if [ $? -ne 0 ]; then
    echo "Build failed! Please check your Rust setup."
    exit 1
fi

# Start the local HTTP server for testing
echo "Starting local Lambda HTTP server..."
export RUST_LOG=info
cargo run &
SERVER_PID=$!

# Give the server time to start
sleep 2

echo ""
echo "Lambda is running at http://localhost:8080"
echo ""
echo "Example requests:"
echo "----------------"
echo "# curl:"
echo 'curl -X GET "http://localhost:8080/api/v3/ticker/price?symbol=BTCUSDT" -H "x-api-key: test-api-key"'
echo ""
echo "Press Ctrl+C to stop the server"

# Wait for user to press Ctrl+C
trap "kill $SERVER_PID; echo ''; echo 'Server stopped'; echo ''; echo 'Local testing complete!'; exit 0" SIGINT
wait $SERVER_PID