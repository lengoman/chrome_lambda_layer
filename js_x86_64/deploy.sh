:q:#!/bin/bash

# Exit on error
set -e

echo "Starting deployment process..."

# Store original directory
ORIGINAL_DIR=$(pwd)

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install it first."
    exit 1
fi

# Check Node.js version (AWS Lambda supports Node.js 14.x, 16.x, 18.x)
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [[ $NODE_VERSION -lt 14 ]]; then
    echo "Node.js version must be 14.x or higher. Current version: $(node -v)"
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials are not configured. Please configure them first."
    exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Using AWS account ID: $ACCOUNT_ID"

# Remove old deployment package if it exists
rm -f function.zip

# Create a temporary directory for the deployment package
rm -rf deploy_tmp
mkdir deploy_tmp

# Copy only necessary files
cp package.json deploy_tmp/
cp package-lock.json deploy_tmp/
cp index.js deploy_tmp/

# Install production dependencies only
cd deploy_tmp
npm install --production

# Remove unnecessary files from node_modules
find . -type d -name "test" -exec rm -rf {} +
find . -type d -name "tests" -exec rm -rf {} +
find . -type d -name "example" -exec rm -rf {} +
find . -type d -name "examples" -exec rm -rf {} +
find . -type d -name "docs" -exec rm -rf {} +
find . -type d -name ".git" -exec rm -rf {} +
find . -type f -name "*.md" -delete
find . -type f -name "*.ts" -delete
find . -type f -name "*.map" -delete
find . -type f -name "LICENSE*" -delete
find . -type f -name "README*" -delete
find . -type f -name "CHANGELOG*" -delete

# Create deployment package
zip -r ../function.zip .

# Clean up
cd ..
rm -rf deploy_tmp

# Create S3 bucket if it doesn't exist
BUCKET_NAME="chrome-lambda-deployments-${ACCOUNT_ID}"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Creating S3 bucket: $BUCKET_NAME"
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --create-bucket-configuration LocationConstraint=$(aws configure get region)
fi

# Upload deployment package to S3
aws s3 cp function.zip "s3://$BUCKET_NAME/function.zip"

# Deploy Lambda function using S3
aws lambda update-function-code \
    --function-name chrome-lambda \
    --s3-bucket "$BUCKET_NAME" \
    --s3-key function.zip

# Clean up
rm -f function.zip

echo "Deployment completed successfully!" 