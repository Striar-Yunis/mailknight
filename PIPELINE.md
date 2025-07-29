# Mailknight Pipeline Documentation

This document explains the simplified, LLM-friendly pipeline structure for Mailknight secure container builds.

## 🎯 Pipeline Simplification Goals

The pipeline has been streamlined to be:
- **LLM-friendly**: Clear documentation and logical flow
- **Automated for @copilot**: Auto-runs when issues are assigned to copilot
- **Self-healing**: Automatically creates fix requests on failures
- **Efficient**: Fewer jobs with consolidated operations

## 📋 Pipeline Structure

### Main Pipeline (`main.yml`)

```yaml
Triggers:
  - Push to main/develop branches
  - Pull requests to main  
  - Weekly schedule (upstream checks)
  - Issues assigned to @copilot
  - Manual workflow dispatch

Jobs:
  1. copilot-autorun      # Auto-trigger for copilot issues
  2. build-and-validate   # Validation and change detection
  3. argocd-build        # Call ArgoCD workflow if changes detected
  4. request-fixes       # Auto-create issues on failures
```

### ArgoCD Workflow (`argocd.yml`)

**Before Simplification**: 8 separate jobs with complex dependencies
**After Simplification**: 3 consolidated jobs

```yaml
Jobs:
  1. build-all-components    # Fetch + Patch + Build (consolidated)
  2. test-and-scan          # Container build + Security scan + FIPS test (matrix)
  3. release                # Release artifacts (conditional)
```

## 🤖 LLM-Friendly Features

### Clear Documentation
- Comprehensive comments explaining each step
- Environment variables clearly defined with purposes
- Component descriptions in `mailknight.yaml`

## 🔧 Common Issues and Fixes

### Issue: curl SSL randomness errors
**Symptom**: `curl: (35) Insufficient randomness`
**Solution**: Install entropy sources (rng-tools, haveged) and use wget fallback
```bash
# Fixed in workflows by adding:
microdnf install -y rng-tools haveged
sudo apt-get install -y rng-tools haveged
# Generate entropy: dd if=/dev/urandom of=/dev/random
# Fallback: wget instead of curl
```

### Issue: GitHub Actions script context errors  
**Symptom**: `ReferenceError: needs is not defined`
**Solution**: Pass job results as script parameters instead of accessing needs context
```javascript
// Before (broken):
${needs.build-and-validate.result === 'failure' ? '...' : ''}

// After (fixed):
const buildResult = '${{ needs.build-and-validate.result }}';
${buildResult === 'failure' ? '...' : ''}
```

### Logical Flow
- Sequential jobs with clear dependencies
- Consolidated operations reduce complexity
- Matrix builds only where necessary

### Error Handling
- Automatic issue creation on failures
- Clear error messages with links to logs
- Continue-on-error for non-critical steps

## 🔄 Copilot Integration

### Auto-run on Issue Assignment
When an issue is assigned to `@copilot`:
1. Pipeline automatically triggers
2. Runs full build and validation
3. Results are available for analysis

### Auto-fix Requests
When pipeline fails:
1. Automatically creates a new issue
2. Assigns to `@copilot` for analysis
3. Includes failure details and links
4. Tagged for easy identification

## 🏗️ Build Process (Simplified)

### For ArgoCD Project:

1. **Consolidated Build** (Single Job):
   ```bash
   # All in one UBI8 container:
   - Fetch ArgoCD v3.0.11 source
   - Apply Mailknight security patches  
   - Build all 6 components with FIPS compliance
   - Generate SBOMs
   ```

2. **Test & Scan Matrix** (Per Component):
   ```bash
   # For each component (server, repo-server, etc.):
   - Build container image
   - Scan for vulnerabilities with Trivy
   - Test FIPS compliance
   - Upload results and SBOMs
   ```

3. **Release** (Conditional):
   ```bash
   # Only on tags or manual dispatch:
   - Collect all artifacts
   - Create release bundles
   - Upload with 30-day retention
   ```

## 📊 Benefits of Simplification

| Aspect | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Jobs** | 10 jobs | 4 jobs | 60% reduction |
| **Artifacts** | 20+ uploads/downloads | 6 uploads/downloads | 70% reduction |
| **Dependencies** | Complex chains | Simple sequential | Much clearer |
| **Documentation** | Minimal | Comprehensive | LLM-friendly |
| **Automation** | Manual only | Copilot integration | Fully automated |

## 🛠️ For Developers

### Running Locally
```bash
# Test specific component
./scripts/build-container.sh argocd v3.0.11 server Dockerfile.server

# Full security scan
./scripts/scan-image.sh argocd v3.0.11 server

# FIPS compliance test
./scripts/test-fips-compliance.sh argocd v3.0.11 server
```

### Adding New Projects
1. Create `projects/myproject/mailknight.yaml`
2. Add container definitions and dependencies
3. Create patches in `patches/myproject/`
4. Update main pipeline change detection

### Debugging Pipeline Issues
1. Check GitHub Actions logs for detailed output
2. Look for auto-created issues tagged `pipeline-failure`
3. Use manual `workflow_dispatch` to test changes
4. Assign issues to `@copilot` for automated analysis

## 🔒 Security & Compliance

All security features are preserved:
- ✅ FIPS 140-2 compliance
- ✅ Vulnerability scanning  
- ✅ Hardened build flags
- ✅ SBOM generation
- ✅ Supply chain security

The simplified pipeline maintains all security requirements while being much easier to understand and maintain.