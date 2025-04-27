#!/bin/bash

set -e

echo "Building Chrome layer..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
LAYER_DIR="$TEMP_DIR/layer"
mkdir -p "$LAYER_DIR"

# Build Docker image
docker build -t chrome-builder -f Dockerfile.chrome .

# Create temporary container
CONTAINER_ID=$(docker create chrome-builder)

# Copy Chrome and its dependencies
echo "Copying Chrome and dependencies from container..."
docker cp $CONTAINER_ID:/opt/google "$LAYER_DIR/"
docker cp $CONTAINER_ID:/lib64 "$LAYER_DIR/"

# Remove container
docker rm $CONTAINER_ID

# Create zip package
echo "Creating Chrome layer zip package..."
cd "$TEMP_DIR"
zip -r chrome-layer-rust.zip layer/
mv chrome-layer-rust.zip ../

# Cleanup
cd ..
rm -rf "$TEMP_DIR"
docker rmi chrome-builder

echo "Chrome layer built successfully at chrome-layer-rust.zip" 