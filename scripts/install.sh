#!/bin/bash
set -euo pipefail

REPO="YOUR_GITHUB_USER/webloc-preview"
INSTALL_DIR="/usr/local/bin"

echo "Installing webloc-preview..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ASSET="webloc-preview-arm64"
elif [ "$ARCH" = "x86_64" ]; then
    ASSET="webloc-preview-x86_64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Download latest release
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET"
echo "Downloading from $DOWNLOAD_URL..."
curl -fsSL "$DOWNLOAD_URL" -o /tmp/webloc-preview

# Install
chmod +x /tmp/webloc-preview
if [ -w "$INSTALL_DIR" ]; then
    mv /tmp/webloc-preview "$INSTALL_DIR/webloc-preview"
else
    sudo mv /tmp/webloc-preview "$INSTALL_DIR/webloc-preview"
fi

echo "Installed to $INSTALL_DIR/webloc-preview"
echo ""
echo "Get started:"
echo "  webloc-preview watch          # Watch ~/ for .webloc files"
echo "  webloc-preview process <path> # Process a specific file"
