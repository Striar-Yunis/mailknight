#!/bin/bash
# Scan container image for vulnerabilities
# Usage: scan-image.sh <project_name> <version>

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version>"
    exit 1
fi

echo "🔍 Scanning $PROJECT_NAME:$VERSION for vulnerabilities"

# Create scan results directory
mkdir -p scan-results

IMAGE_NAME="mailknight/$PROJECT_NAME:$VERSION"
SCAN_DATE=$(date -Iseconds)

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "❌ Image $IMAGE_NAME not found"
    exit 1
fi

# Run Trivy scans
echo "🔍 Running vulnerability scan..."

# Vulnerability scan
trivy image \
    --format json \
    --output scan-results/trivy-vulnerabilities.json \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    "$IMAGE_NAME"

# Configuration scan
trivy config \
    --format json \
    --output scan-results/trivy-config.json \
    projects/"$PROJECT_NAME"/

# Secret scan
trivy fs \
    --format json \
    --output scan-results/trivy-secrets.json \
    --scanners secret \
    source/"$PROJECT_NAME"/

# Generate summary report
echo "📊 Generating scan summary..."

# Count vulnerabilities by severity
HIGH_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' scan-results/trivy-vulnerabilities.json)
CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' scan-results/trivy-vulnerabilities.json)

# Check for secrets
SECRET_COUNT=$(jq '[.Results[]?.Secrets[]?] | length' scan-results/trivy-secrets.json)

# Generate scan report
cat > scan-results/scan-summary.json << EOF
{
  "project": "$PROJECT_NAME",
  "version": "$VERSION",
  "image": "$IMAGE_NAME",
  "scan_date": "$SCAN_DATE",
  "scanner": "trivy",
  "results": {
    "vulnerabilities": {
      "critical": $CRITICAL_COUNT,
      "high": $HIGH_COUNT,
      "total": $(($CRITICAL_COUNT + $HIGH_COUNT))
    },
    "secrets": $SECRET_COUNT,
    "scan_status": "$([ $(($CRITICAL_COUNT + $HIGH_COUNT)) -eq 0 ] && echo "PASS" || echo "FAIL")"
  },
  "reports": {
    "vulnerabilities": "trivy-vulnerabilities.json",
    "configuration": "trivy-config.json",
    "secrets": "trivy-secrets.json"
  }
}
EOF

# Check VEX overrides
VEX_DIR="vex/$PROJECT_NAME"
if [[ -d "$VEX_DIR" ]]; then
    echo "🔍 Checking VEX overrides..."
    
    # Apply VEX overrides (simplified implementation)
    OVERRIDE_COUNT=0
    for vex_file in "$VEX_DIR"/*.json; do
        if [[ -f "$vex_file" ]]; then
            ((OVERRIDE_COUNT++))
        fi
    done
    
    if [[ $OVERRIDE_COUNT -gt 0 ]]; then
        echo "📋 Found $OVERRIDE_COUNT VEX override(s)"
        jq --arg overrides "$OVERRIDE_COUNT" '.results.vex_overrides = ($overrides | tonumber)' scan-results/scan-summary.json > scan-results/scan-summary.tmp
        mv scan-results/scan-summary.tmp scan-results/scan-summary.json
    fi
fi

# Display results
echo ""
echo "📊 Scan Results Summary:"
echo "   Critical vulnerabilities: $CRITICAL_COUNT"
echo "   High vulnerabilities: $HIGH_COUNT"
echo "   Secrets found: $SECRET_COUNT"
echo ""

# Quality gate: fail if critical or high vulnerabilities found
if [[ $(($CRITICAL_COUNT + $HIGH_COUNT)) -gt 0 ]]; then
    echo "❌ Security scan FAILED: Found $(($CRITICAL_COUNT + $HIGH_COUNT)) high/critical vulnerabilities"
    
    # Show vulnerability details
    echo ""
    echo "🚨 Vulnerability Details:"
    jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL") | "  - \(.VulnerabilityID): \(.Title) (\(.Severity))"' scan-results/trivy-vulnerabilities.json
    
    exit 1
else
    echo "✅ Security scan PASSED: No high/critical vulnerabilities found"
fi

# Generate GitLab CI reports
cp scan-results/trivy-vulnerabilities.json scan-results/trivy-dependency.json
cp scan-results/trivy-vulnerabilities.json scan-results/trivy-container.json

echo "📄 Scan reports saved to scan-results/"