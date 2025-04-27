#!/bin/bash

# Exit on any error
set -e

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="chrome-lambda-deployments-$AWS_ACCOUNT_ID"

echo "Building Chromium layer..."
docker build -t chromium-builder .

echo "Creating container..."
CONTAINER_ID=$(docker create chromium-builder /bin/sh)

echo "Copying layer package..."
docker cp $CONTAINER_ID:/chromium-layer.zip ./chromium-layer.zip

echo "Cleaning up..."
docker rm $CONTAINER_ID
docker rmi chromium-builder

echo "Uploading layer to S3..."
aws s3 cp chromium-layer.zip "s3://$BUCKET_NAME/chromium-layer.zip"

echo "Publishing layer..."
LAYER_VERSION=$(aws lambda publish-layer-version \
    --layer-name chromium-v114 \
    --description "Chromium v114.0.0 for Lambda" \
    --content "S3Bucket=$BUCKET_NAME,S3Key=chromium-layer.zip" \
    --compatible-architectures x86_64 \
    --compatible-runtimes provided.al2023 \
    --query 'Version' \
    --output text)

echo "Chromium layer built and published successfully: Version $LAYER_VERSION"
ls -lh chromium-layer.zip 