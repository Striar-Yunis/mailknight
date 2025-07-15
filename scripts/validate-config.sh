#!/bin/bash
# Mailknight Configuration Validator
# Validates pipeline configuration and dependencies

set -euo pipefail

echo "🔍 Validating Mailknight pipeline configuration..."

# Check required environment variables (CI context)
if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
    # We're in a CI environment, but different variables are required for different CI systems
    if [[ -n "${CI_PROJECT_DIR:-}" ]]; then
        # GitLab CI (legacy support)
        echo "ℹ️  Detected GitLab CI environment"
    elif [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
        # GitHub Actions
        echo "ℹ️  Detected GitHub Actions environment"
    else
        echo "ℹ️  CI environment detected but workspace variable not found"
    fi
else
    echo "ℹ️  Running in local development mode"
fi

# Validate directory structure
REQUIRED_DIRS=(
    "projects"
    "patches"
    "vex"
    "scripts"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "❌ Required directory $dir does not exist"
        exit 1
    fi
done

# Validate GitHub Actions workflow files
WORKFLOW_FILES=(
    ".github/workflows/main.yml"
)

for file in "${WORKFLOW_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ Required workflow file $file does not exist"
        exit 1
    fi
    
    # Basic YAML syntax check
    if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo "❌ Invalid YAML syntax in $file"
        exit 1
    fi
done

# Check if we have GitHub Actions workflows for projects
if [[ ! -d ".github/workflows" ]] || [[ "$(find .github/workflows -name '*.yml' | wc -l)" -eq 0 ]]; then
    echo "⚠️  No GitHub Actions workflows found"
fi

# Validate script permissions
find scripts -name "*.sh" -exec chmod +x {} \;

echo "✅ Pipeline configuration validation passed"
echo "📊 Summary:"
echo "   - Projects: $(find projects -maxdepth 1 -type d | wc -l | awk '{print $1-1}')"
echo "   - Scripts: $(find scripts -name "*.sh" | wc -l)"
echo "   - Patches: $(find patches -name "*.patch" | wc -l)"
echo "   - GitHub Actions workflows: $(find .github/workflows -name "*.yml" 2>/dev/null | wc -l)"