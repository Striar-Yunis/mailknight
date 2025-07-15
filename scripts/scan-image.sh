#!/bin/bash
# Scan container image for vulnerabilities
# Usage: scan-image.sh <project_name> <version> [container_name]

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"
CONTAINER_NAME="${3:-main}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version> [container_name]"
    exit 1
fi

echo "🔍 Scanning $PROJECT_NAME:$VERSION (component: $CONTAINER_NAME) for vulnerabilities"

# Create component-specific scan results directory
mkdir -p "scan-results/$CONTAINER_NAME"

IMAGE_NAME="mailknight/$PROJECT_NAME-$CONTAINER_NAME:$VERSION-mailknight"
SCAN_DATE=$(date -Iseconds)

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "❌ Image $IMAGE_NAME not found"
    exit 1
fi

# Run Trivy scans
echo "🔍 Running vulnerability scan for $CONTAINER_NAME component..."

# Vulnerability scan
trivy image \
    --format json \
    --output "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json" \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    "$IMAGE_NAME"

# Configuration scan
trivy config \
    --format json \
    --output "scan-results/$CONTAINER_NAME/trivy-config.json" \
    "projects/$PROJECT_NAME/"

# Secret scan on the specific Dockerfile
if [[ -f "projects/$PROJECT_NAME/Dockerfile.$CONTAINER_NAME" ]]; then
    trivy fs \
        --format json \
        --output "scan-results/$CONTAINER_NAME/trivy-secrets.json" \
        --scanners secret \
        "projects/$PROJECT_NAME/Dockerfile.$CONTAINER_NAME"
else
    # Fallback to general project directory
    trivy fs \
        --format json \
        --output "scan-results/$CONTAINER_NAME/trivy-secrets.json" \
        --scanners secret \
        "projects/$PROJECT_NAME/"
fi

# Generate summary report
echo "📊 Generating scan summary for $CONTAINER_NAME..."

# Count vulnerabilities by severity
HIGH_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json")
CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json")

# Check for secrets
SECRET_COUNT=$(jq '[.Results[]?.Secrets[]?] | length' "scan-results/$CONTAINER_NAME/trivy-secrets.json")

# Generate component-specific scan report
cat > "scan-results/$CONTAINER_NAME/scan-summary.json" << EOF
{
  "project": "$PROJECT_NAME",
  "component": "$CONTAINER_NAME",
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
    echo "🔍 Checking VEX overrides for $CONTAINER_NAME..."
    
    # Apply VEX overrides (simplified implementation)
    OVERRIDE_COUNT=0
    for vex_file in "$VEX_DIR"/*.json; do
        if [[ -f "$vex_file" ]]; then
            # Check if this VEX applies to the current container
            if grep -q "$CONTAINER_NAME\|$IMAGE_NAME" "$vex_file" 2>/dev/null; then
                ((OVERRIDE_COUNT++))
            fi
        fi
    done
    
    if [[ $OVERRIDE_COUNT -gt 0 ]]; then
        echo "📋 Found $OVERRIDE_COUNT VEX override(s) for $CONTAINER_NAME"
        jq --arg overrides "$OVERRIDE_COUNT" '.results.vex_overrides = ($overrides | tonumber)' "scan-results/$CONTAINER_NAME/scan-summary.json" > "scan-results/$CONTAINER_NAME/scan-summary.tmp"
        mv "scan-results/$CONTAINER_NAME/scan-summary.tmp" "scan-results/$CONTAINER_NAME/scan-summary.json"
    fi
fi

# Display results
echo ""
echo "📊 Scan Results Summary for $CONTAINER_NAME:"
echo "   Critical vulnerabilities: $CRITICAL_COUNT"
echo "   High vulnerabilities: $HIGH_COUNT"
echo "   Secrets found: $SECRET_COUNT"
echo ""

# Quality gate: fail if critical or high vulnerabilities found
if [[ $(($CRITICAL_COUNT + $HIGH_COUNT)) -gt 0 ]]; then
    echo "❌ Security scan FAILED for $CONTAINER_NAME: Found $(($CRITICAL_COUNT + $HIGH_COUNT)) high/critical vulnerabilities"
    
    # Show vulnerability details
    echo ""
    echo "🚨 Vulnerability Details for $CONTAINER_NAME:"
    jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL") | "  - \(.VulnerabilityID): \(.Title) (\(.Severity))"' "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json"
    
    exit 1
else
    echo "✅ Security scan PASSED for $CONTAINER_NAME: No high/critical vulnerabilities found"
fi

# Generate CI reports (component-specific)
cp "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json" "scan-results/$CONTAINER_NAME/trivy-dependency.json"
cp "scan-results/$CONTAINER_NAME/trivy-vulnerabilities.json" "scan-results/$CONTAINER_NAME/trivy-container.json"

echo "📄 Scan reports for $CONTAINER_NAME saved to scan-results/$CONTAINER_NAME/"