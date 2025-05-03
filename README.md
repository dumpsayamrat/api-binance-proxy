# Binance API Proxy Lambda

## The Problem

When accessing the Binance API from certain geographic locations, particularly from US-based servers such as GitHub Actions runners, requests are often blocked due to Binance's regional restrictions. This creates a significant challenge for automated trading systems, CI/CD pipelines, and monitoring tools that need to interact with Binance from these restricted locations.

This repository provides a solution by creating a proxy service hosted on AWS Lambda that can relay requests to Binance API endpoints. Since AWS Lambda functions can be deployed in regions where Binance access is permitted, this effectively bypasses the geographic restrictions while maintaining security through API key authentication.

## Architecture Diagram

```
┌───────────────┐      ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│               │      │               │      │               │      │               │
│  API Client   │─────▶│  API Gateway  │─────▶│    Lambda     │─────▶│  Binance API  │
│  (with API Key)│      │  (with Auth)  │      │   (Proxy)     │      │  api2.binance.com │
│               │◀─────│               │◀─────│               │◀─────│               │
└───────────────┘      └───────────────┘      └───────────────┘      └───────────────┘
```

## Features

- Proxies all requests to `https://api2.binance.com/api/**/*` endpoints
- Deployed as an AWS Lambda function with API Gateway 
- API key authentication for security
- GitHub Actions CI/CD pipeline for automated deployment
- Local testing with an embedded HTTP server
- Terraform infrastructure as code for AWS resources

## Local Development and Testing

### Prerequisites

- Rust and Cargo installed
- For Windows: PowerShell
- For Linux/Mac: Bash

### Building and Running Locally

#### Windows

```powershell
# Run the local test script
.\local-test.ps1
```

#### Linux/Mac

```bash
# Make the script executable
chmod +x local-test.sh

# Run the local test script
./local-test.sh
```

### Making Test Requests

You can test the proxy locally using:

#### PowerShell

```powershell
Invoke-WebRequest -Uri "http://localhost:8080/api/v3/ticker/price?symbol=BTCUSDT" -Headers @{"x-api-key"="test-api-key"} -Method GET | Select-Object -ExpandProperty Content | ConvertFrom-Json
```

#### cURL (Linux/Mac/Windows with curl installed)

```bash
curl -X GET "http://localhost:8080/api/v3/ticker/price?symbol=BTCUSDT" -H "x-api-key: test-api-key"
```


### Automated Deployment with GitHub Actions

The project includes a GitHub Actions workflow that automatically deploys to AWS when you push to the main branch:

1. Builds the Rust Lambda function
2. Cross-compiles for Amazon Linux
3. Creates a deployment package (zip file)
4. Deploys all infrastructure using Terraform
5. Outputs the API Gateway URL and API key

To trigger a deployment:
- Push to the `main` branch, or
- Manually trigger the workflow from the "Actions" tab in GitHub

### Manual Deployment

If you prefer to deploy manually:

```bash
# Build for Lambda (requires a Linux environment or Docker)
cargo build --release --target x86_64-unknown-linux-musl

# Package the Lambda function
mkdir -p lambda-package
cp target/x86_64-unknown-linux-musl/release/api-binance-proxy lambda-package/bootstrap
cd lambda-package
zip -r lambda-function.zip bootstrap
mv lambda-function.zip ../terraform/

# Deploy with Terraform
cd ../terraform
terraform init
terraform apply
```

## Using the Deployed API

After deployment, you'll get an API Gateway URL and an API key. Use them to make requests:

```bash
curl -X GET "https://your-api-id.execute-api.region.amazonaws.com/prod/api/v3/ticker/price?symbol=BTCUSDT" \
  -H "x-api-key: your-api-key"
```

## GitHub Actions Configuration Guide

This project uses GitHub Actions for CI/CD. To set it up:

1. Go to your repository on GitHub
2. Navigate to Settings → Secrets and Variables → Actions
3. Add the following secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION`
   - `TF_STATE_BUCKET`

## Terraform Infrastructure

The Terraform configuration creates:
- AWS Lambda function
- IAM roles and policies
- API Gateway with API key authentication
- CloudWatch Logs for monitoring

You can customize the deployment by modifying:
- `terraform/main.tf` - Main infrastructure code
- `terraform/variables.tf` - Configuration variables