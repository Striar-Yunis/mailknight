#!/bin/bash
# Mailknight Configuration Validator
# Validates pipeline configuration and dependencies

set -euo pipefail

echo "🔍 Validating Mailknight pipeline configuration..."

# Check required environment variables (CI context)
if [[ -n "${CI:-}" ]]; then
    REQUIRED_VARS=(
        "CI_PROJECT_DIR"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "❌ Required environment variable $var is not set"
            exit 1
        fi
    done
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

# Validate GitLab CI files
CI_FILES=(
    ".gitlab-ci.yml"
    ".mailknight.yml"
)

for file in "${CI_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "❌ Required CI file $file does not exist"
        exit 1
    fi
    
    # Basic YAML syntax check
    if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        echo "❌ Invalid YAML syntax in $file"
        exit 1
    fi
done

# Check if we have any projects configured
if [[ ! "$(find projects -name '.gitlab-ci.yml' | wc -l)" -gt 0 ]]; then
    echo "⚠️  No projects with CI configuration found"
fi

# Validate script permissions
find scripts -name "*.sh" -exec chmod +x {} \;

echo "✅ Pipeline configuration validation passed"
echo "📊 Summary:"
echo "   - Projects: $(find projects -maxdepth 1 -type d | wc -l | awk '{print $1-1}')"
echo "   - Scripts: $(find scripts -name "*.sh" | wc -l)"
echo "   - Patches: $(find patches -name "*.patch" | wc -l)"