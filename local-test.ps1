# PowerShell script for local testing of the Binance API Proxy Lambda on Windows
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   Binance API Proxy - Local Testing Tool    " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Build the project with proper dependencies
Write-Host "Building the Lambda function..." -ForegroundColor Green
cargo build

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed! Please check your Rust setup." -ForegroundColor Red
    exit 1
}

# Set environment variable and start the server
Write-Host "Starting local Lambda HTTP server..." -ForegroundColor Green
$env:RUST_LOG="info"

# Start the application in a new window to avoid blocking this script
$process = Start-Process -PassThru -FilePath "cargo" -ArgumentList "run" -NoNewWindow

if ($null -eq $process) {
    Write-Host "Failed to start the server. Please check your Rust setup." -ForegroundColor Red
    exit 1
}

# Give the server time to start
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Lambda is running at http://localhost:8080" -ForegroundColor Cyan
Write-Host ""
Write-Host "Example requests:" -ForegroundColor Yellow
Write-Host "---------------- " -ForegroundColor Yellow
Write-Host "# PowerShell:" -ForegroundColor Magenta
Write-Host 'Invoke-WebRequest -Uri "http://localhost:8080/api/v3/ticker/price?symbol=BTCUSDT" -Headers @{"x-api-key"="test-api-key"} -Method GET | Select-Object -ExpandProperty Content | ConvertFrom-Json | Format-List' -ForegroundColor Yellow
Write-Host ""
Write-Host "# curl (if installed):" -ForegroundColor Magenta
Write-Host 'curl -X GET "http://localhost:8080/api/v3/ticker/price?symbol=BTCUSDT" -H "x-api-key: test-api-key"' -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to stop the test server..." -ForegroundColor Red

# Wait for user input to stop
$null = Read-Host

# Stop the server process
if ($process -ne $null) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Local test server stopped" -ForegroundColor Green
}

Write-Host ""
Write-Host "Local testing complete!" -ForegroundColor Cyan