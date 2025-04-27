#!/bin/bash

# Exit on any error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials are not configured. Please run 'aws configure' first."
    exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 bucket for deployment if it doesn't exist
BUCKET_NAME="chrome-lambda-deployments-$AWS_ACCOUNT_ID"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Creating S3 bucket for deployment..."
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region us-east-1
fi

# Get Chromium layer ARN
echo "Getting Chromium layer ARN..."
CHROMIUM_LAYER_ARN="arn:aws:lambda:us-east-1:$AWS_ACCOUNT_ID:layer:chromium-v114:42"

# Verify NSS libraries in the layer
echo "Verifying NSS libraries in the layer..."
LAYER_DIR="layer"
if [ -d "$LAYER_DIR" ]; then
    echo "Checking for libnss3.so in the layer..."
    if unzip -l "$LAYER_DIR/chromium-layer.zip" | grep -q "libnss3.so"; then
        echo "✅ libnss3.so found in the layer"
    else
        echo "❌ libnss3.so NOT found in the layer. Please rebuild the layer."
        exit 1
    fi
    
    echo "Listing all NSS libraries in the layer:"
    unzip -l "$LAYER_DIR/chromium-layer.zip" | grep -E "libnss|libnspr"
else
    echo "Layer directory not found. Skipping verification."
fi

# Build Lambda function
echo "Building Lambda function..."
cargo lambda build --release --target x86_64-unknown-linux-gnu

# Create deployment package
echo "Creating deployment package..."
cd target/lambda/chrome-lambda-rust
zip -r ../../../rust-function.zip bootstrap
cd ../../..

# Upload deployment package to S3
echo "Uploading deployment package to S3..."
aws s3 cp rust-function.zip "s3://$BUCKET_NAME/rust-function.zip"

# Create/update Lambda function
echo "Creating/updating Lambda function..."
aws lambda create-function \
    --function-name chrome-lambda-rust \
    --runtime provided.al2023 \
    --handler bootstrap \
    --role arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda-role \
    --zip-file fileb://rust-function.zip \
    --memory-size 1024 \
    --timeout 60 \
    --environment "Variables={RUST_BACKTRACE=1,CHROME_PATH=/opt/chromium/chrome,LD_LIBRARY_PATH=/opt/chromium/lib:/usr/lib64,NSS_DB_PATH=/opt/etc/pki/nssdb,CHROME_FLAGS=--no-sandbox --headless --disable-gpu --disable-dev-shm-usage --disable-setuid-sandbox --disable-namespace-sandbox}" \
    --layers "$CHROMIUM_LAYER_ARN" \
    --architectures x86_64 2>/dev/null || \
    aws lambda update-function-code \
        --function-name chrome-lambda-rust \
        --zip-file fileb://rust-function.zip >/dev/null

echo "Waiting for function update to complete..."
sleep 5

echo "Updating function configuration..."
aws lambda update-function-configuration \
    --function-name chrome-lambda-rust \
    --runtime provided.al2023 \
    --handler bootstrap \
    --role arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda-role \
    --memory-size 1024 \
    --timeout 60 \
    --environment "Variables={RUST_BACKTRACE=1,CHROME_PATH=/opt/chromium/chrome,LD_LIBRARY_PATH=/opt/chromium/lib:/usr/lib64,NSS_DB_PATH=/opt/etc/pki/nssdb,CHROME_FLAGS=--no-sandbox --headless --disable-gpu --disable-dev-shm-usage --disable-setuid-sandbox --disable-namespace-sandbox}" \
    --layers "$CHROMIUM_LAYER_ARN"

# Clean up
echo "Cleaning up..."
rm -f rust-function.zip

echo "Deployment complete!" 