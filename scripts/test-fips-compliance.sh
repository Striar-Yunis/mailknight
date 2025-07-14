#!/bin/bash
# Test FIPS compliance for container image
# Usage: test-fips-compliance.sh <project_name> <version> [container_name]

set -euo pipefail

PROJECT_NAME="${1:-}"
VERSION="${2:-}"
CONTAINER_NAME="${3:-main}"

if [[ -z "$PROJECT_NAME" || -z "$VERSION" ]]; then
    echo "Usage: $0 <project_name> <version> [container_name]"
    exit 1
fi

echo "🔐 Testing FIPS compliance for $PROJECT_NAME:$VERSION (component: $CONTAINER_NAME)"

# Create component-specific test results directory
mkdir -p "test-results/$CONTAINER_NAME"

IMAGE_NAME="mailknight/$PROJECT_NAME-$CONTAINER_NAME:$VERSION-mailknight"
TEST_DATE=$(date -Iseconds)

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "❌ Image $IMAGE_NAME not found"
    exit 1
fi

# Initialize test results
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Helper function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo "🧪 Running test: $test_name"
    
    if eval "$test_command"; then
        if [[ "$expected_result" == "pass" ]]; then
            echo "  ✅ PASS: $test_name"
            TEST_RESULTS+=("PASS: $test_name")
            ((TESTS_PASSED++))
        else
            echo "  ❌ FAIL: $test_name (unexpected success)"
            TEST_RESULTS+=("FAIL: $test_name (unexpected success)")
            ((TESTS_FAILED++))
        fi
    else
        if [[ "$expected_result" == "fail" ]]; then
            echo "  ✅ PASS: $test_name (expected failure)"
            TEST_RESULTS+=("PASS: $test_name (expected failure)")
            ((TESTS_PASSED++))
        else
            echo "  ❌ FAIL: $test_name"
            TEST_RESULTS+=("FAIL: $test_name")
            ((TESTS_FAILED++))
        fi
    fi
}

# Test 1: Check FIPS mode in container
run_test "FIPS mode enabled in container" \
    "docker run --rm '$IMAGE_NAME' sh -c 'test \"\$(cat /proc/sys/crypto/fips_enabled 2>/dev/null || echo 0)\" -eq 1'" \
    "pass"

# Test 2: OpenSSL FIPS support
run_test "OpenSSL FIPS support" \
    "docker run --rm '$IMAGE_NAME' sh -c 'openssl version | grep -i fips'" \
    "pass"

# Test 3: Environment variables for FIPS
run_test "FIPS environment variables" \
    "docker run --rm '$IMAGE_NAME' sh -c 'test \"\$OPENSSL_FORCE_FIPS_MODE\" = \"1\"'" \
    "pass"

# Test 4: Non-root user
run_test "Running as non-root user" \
    "docker run --rm '$IMAGE_NAME' sh -c 'test \"\$(id -u)\" -ne 0'" \
    "pass"

# Test 5: No unnecessary tools
run_test "No curl in final image" \
    "docker run --rm '$IMAGE_NAME' sh -c 'which curl'" \
    "fail"

run_test "No wget in final image" \
    "docker run --rm '$IMAGE_NAME' sh -c 'which wget'" \
    "fail"

# Test 6: Binary hardening (check for stack protection)
if command -v checksec &> /dev/null; then
    run_test "Stack protection enabled" \
        "docker run --rm '$IMAGE_NAME' sh -c 'checksec --file=/usr/local/bin/argocd | grep -i \"stack canary.*yes\"'" \
        "pass"
        
    run_test "RELRO enabled" \
        "docker run --rm '$IMAGE_NAME' sh -c 'checksec --file=/usr/local/bin/argocd | grep -i \"relro.*full\"'" \
        "pass"
else
    echo "⚠️  checksec not available, skipping binary hardening tests"
fi

# Test 7: Component-specific FIPS tests
case "$PROJECT_NAME" in
    "argocd")
        case "$CONTAINER_NAME" in
            "server")
                # Test ArgoCD server can show help
                run_test "ArgoCD server help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            "repo-server")
                # Test ArgoCD repo-server can show help
                run_test "ArgoCD repo-server help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            "application-controller")
                # Test ArgoCD application-controller can show help
                run_test "ArgoCD application-controller help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            "applicationset-controller")
                # Test ArgoCD applicationset-controller can show help  
                run_test "ArgoCD applicationset-controller help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            "dex")
                # Test ArgoCD dex can show help
                run_test "ArgoCD dex help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            "notification")
                # Test ArgoCD notification can show help
                run_test "ArgoCD notification help" \
                    "docker run --rm '$IMAGE_NAME' --help" \
                    "pass"
                ;;
            *)
                # Generic ArgoCD test for unknown containers
                run_test "ArgoCD version command" \
                    "docker run --rm '$IMAGE_NAME' version --client" \
                    "pass"
                ;;
        esac
        ;;
esac

# Generate test report
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
SUCCESS_RATE=$(echo "scale=2; $TESTS_PASSED * 100 / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0")

# Generate JUnit XML report (component-specific)
cat > "test-results/$CONTAINER_NAME/fips-compliance.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="FIPS Compliance Tests - $CONTAINER_NAME" tests="$TOTAL_TESTS" failures="$TESTS_FAILED" time="$(date +%s)">
EOF

for result in "${TEST_RESULTS[@]}"; do
    test_name=$(echo "$result" | cut -d: -f2- | xargs)
    if [[ "$result" == PASS:* ]]; then
        echo "  <testcase name=\"$test_name\" classname=\"FIPSCompliance.$CONTAINER_NAME\"/>" >> "test-results/$CONTAINER_NAME/fips-compliance.xml"
    else
        echo "  <testcase name=\"$test_name\" classname=\"FIPSCompliance.$CONTAINER_NAME\">" >> "test-results/$CONTAINER_NAME/fips-compliance.xml"
        echo "    <failure message=\"Test failed\">$result</failure>" >> "test-results/$CONTAINER_NAME/fips-compliance.xml"
        echo "  </testcase>" >> "test-results/$CONTAINER_NAME/fips-compliance.xml"
    fi
done

echo "</testsuite>" >> "test-results/$CONTAINER_NAME/fips-compliance.xml"

# Generate JSON report (component-specific)
cat > "test-results/$CONTAINER_NAME/fips-compliance.json" << EOF
{
  "project": "$PROJECT_NAME",
  "component": "$CONTAINER_NAME",
  "version": "$VERSION",
  "image": "$IMAGE_NAME",
  "test_date": "$TEST_DATE",
  "results": {
    "total_tests": $TOTAL_TESTS,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "success_rate": "$SUCCESS_RATE%"
  },
  "test_details": [
$(IFS=$'\n'; echo "${TEST_RESULTS[*]}" | sed 's/\(.*\)/    "\1"/' | paste -sd, -)
  ],
  "compliance_status": "$([ $TESTS_FAILED -eq 0 ] && echo "COMPLIANT" || echo "NON_COMPLIANT")"
}
EOF

# Display results
echo ""
echo "📊 FIPS Compliance Test Results for $CONTAINER_NAME:"
echo "   Total tests: $TOTAL_TESTS"
echo "   Passed: $TESTS_PASSED"
echo "   Failed: $TESTS_FAILED"
echo "   Success rate: $SUCCESS_RATE%"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ FIPS Compliance: COMPLIANT"
    echo "🔐 Image $IMAGE_NAME meets FIPS compliance requirements"
else
    echo "❌ FIPS Compliance: NON_COMPLIANT"
    echo "🚨 Image $IMAGE_NAME does not meet FIPS compliance requirements"
    echo ""
    echo "Failed tests:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == FAIL:* ]]; then
            echo "  - $(echo "$result" | cut -d: -f2- | xargs)"
        fi
    done
    exit 1
fi

echo "📄 Test reports for $CONTAINER_NAME saved to test-results/$CONTAINER_NAME/"