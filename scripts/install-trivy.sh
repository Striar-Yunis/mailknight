#!/bin/bash
# Install Trivy security scanner
# Usage: install-trivy.sh

set -euo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.48.3}"

echo "📥 Installing Trivy security scanner version $TRIVY_VERSION"

# Check if Trivy is already installed
if command -v trivy &> /dev/null; then
    INSTALLED_VERSION=$(trivy --version | head -n1 | cut -d' ' -f2)
    if [[ "$INSTALLED_VERSION" == "$TRIVY_VERSION" ]]; then
        echo "✅ Trivy $TRIVY_VERSION is already installed"
        exit 0
    fi
fi

# Download and install Trivy
TRIVY_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

echo "📦 Downloading Trivy from: $TRIVY_URL"
curl -sL "$TRIVY_URL" | tar -xz -C /tmp

# Install to /usr/local/bin (use sudo only if available)
if command -v sudo &> /dev/null; then
    sudo mv /tmp/trivy /usr/local/bin/trivy
    sudo chmod +x /usr/local/bin/trivy
else
    mv /tmp/trivy /usr/local/bin/trivy
    chmod +x /usr/local/bin/trivy
fi

# Verify installation
if trivy --version; then
    echo "✅ Trivy $TRIVY_VERSION installed successfully"
else
    echo "❌ Failed to install Trivy"
    exit 1
fi