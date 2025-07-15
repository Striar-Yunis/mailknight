# Mailknight Development Guide

Mailknight is a secure software supply chain automation system that builds FIPS-compliant, hardened container images for open source projects. This guide covers the development workflow, adding new projects, and understanding the build pipeline architecture.

## CI/CD System

Mailknight uses **GitHub Actions** for comprehensive CI/CD automation:

### GitHub Actions Architecture
- **Main Workflow**: `.github/workflows/main.yml` - validation and coordination  
- **Project Workflows**: `.github/workflows/argocd.yml` - ArgoCD specific builds
- **Matrix Builds**: Automatic generation of parallel builds for each project component

## Architecture

### Multi-Container Project Support

Mailknight supports projects that consist of multiple containers with different build requirements. Each container can have:

- **Individual Dockerfiles**: Component-specific build configurations  
- **Separate Dependencies**: Different runtime and build dependencies
- **Independent Scanning**: Vulnerability scanning per container
- **Component Testing**: FIPS compliance testing per container
- **Isolated Artifacts**: Separate SBOMs, scan results, and test reports

### Current Implementation: ArgoCD Example

The ArgoCD project demonstrates multi-container support with these **6 components**:

| Component | Description | Key Dependencies | Port(s) |
|-----------|-------------|------------------|---------|
| `server` | API Server & Web UI | git, openssh-client, ca-certificates | 8080, 8083 |
| `repo-server` | Repository Server | git, git-lfs, helm, kustomize, gnupg | 8081 |
| `application-controller` | Main Controller | ca-certificates | - |
| `applicationset-controller` | ApplicationSet Controller | ca-certificates | - |
| `dex` | Authentication Service | ca-certificates | 5556, 5557, 5558 |
| `notification` | Notification Controller | ca-certificates | - |

### Project Configuration

Each project defines its containers in a `mailknight.yaml` configuration file:

```yaml
apiVersion: v1
kind: MailknightProject
metadata:
  name: argocd
  description: "ArgoCD GitOps continuous delivery tool"
spec:
  upstream:
    repository: "https://github.com/argoproj/argo-cd.git"
    version: "v3.0.11"
  
  # Global project settings
  settings:
    goVersion: "1.21"
    nodeVersion: "18"
    fipsEnabled: true
    buildFlags:
      cflags: "-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE"
      ldflags: "-Wl,-z,relro,-z,now -pie"
  
  containers:
    server:
      description: "ArgoCD API Server"
      dockerfile: "Dockerfile.server"
      entrypoint: "/usr/local/bin/argocd-server"
      ports: [8080, 8083]
      dependencies:
        - git
        - ca-certificates
        - openssh-client
    
    repo-server:
      description: "ArgoCD Repository Server"
      dockerfile: "Dockerfile.repo-server"
      entrypoint: "/usr/local/bin/argocd-repo-server"
      dependencies:
        - git
        - git-lfs
        - helm
        - kustomize
```

## Directory Structure

```
mailknight/
├── .github/workflows/          # GitHub Actions workflows
│   ├── main.yml               # Main validation workflow
│   └── argocd.yml             # ArgoCD-specific workflow
├── projects/
│   └── argocd/
│       ├── mailknight.yaml     # Project configuration
│       ├── Dockerfile          # Base Dockerfile (if needed)
│       ├── Dockerfile.server   # Server component
│       ├── Dockerfile.repo-server # Repository server
│       ├── Dockerfile.controller # Application controller
│       ├── Dockerfile.applicationset-controller # ApplicationSet controller  
│       ├── Dockerfile.dex      # Authentication service
│       └── Dockerfile.notification # Notification controller
├── patches/argocd/             # Security patches by version
│   ├── common/                # Common patches across versions
│   ├── v3.0.11/              # Current version patches
│   └── (older versions)      # Previous version patches
├── vex/argocd/                 # VEX vulnerability statements
│   ├── 2025-001.json         # Example VEX statement
│   └── v3.0.11-2025-001.json # Version-specific VEX
└── scripts/                    # Build automation scripts
    ├── apply-patches.sh       # Apply security patches
    ├── build-container.sh     # Build individual containers
    ├── build-project.sh       # Build project binaries
    ├── fetch-upstream.sh      # Fetch upstream source
    ├── install-trivy.sh       # Install vulnerability scanner
    ├── release-artifacts.sh   # Package and release
    ├── scan-image.sh          # Vulnerability scanning
    ├── test-fips-compliance.sh # FIPS compliance testing
    └── validate-config.sh     # Configuration validation
```

## Build Process

### 1. Source Preparation (Shared)
- **Fetch**: Download upstream source code from GitHub
- **Patch**: Apply Mailknight security patches for FIPS compliance
- **Build**: Compile all binaries with hardened flags (shared across containers)

### 2. Container Building (Per Component)  
- **Matrix Build**: Build jobs generated for each container defined in `mailknight.yaml`
- **Component Dockerfiles**: Use component-specific Dockerfiles (e.g., `Dockerfile.server`)
- **Dependencies**: Install only required dependencies per component
- **SBOM Generation**: Generate Software Bill of Materials per container

### 3. Security Scanning (Per Component)
- **Trivy Scanning**: Container and dependency vulnerability scanning
- **VEX Application**: Apply vulnerability exception statements  
- **Secret Scanning**: Check for embedded secrets
- **Quality Gate**: Block builds on HIGH/CRITICAL unmitigated CVEs

### 4. FIPS Testing (Per Component)
- **FIPS Verification**: Verify OpenSSL FIPS mode is enabled
- **Component Tests**: Component-specific functionality tests
- **Runtime Security**: Check container hardening and non-root execution

### 5. Release (Multi-Component)
- **Artifact Packaging**: Bundle all container images and metadata
- **Tagging**: Apply semantic versioning (`v3.0.11-mailknight`)
- **Release Notes**: Document security fixes and component changes

## Current ArgoCD Implementation

The ArgoCD project showcases the complete multi-container workflow:

### Components Built
- **server**: API server with Git and SSH tools for repository access
- **repo-server**: Repository server with Git, Helm, Kustomize for manifest processing  
- **application-controller**: Main controller with minimal dependencies
- **applicationset-controller**: ApplicationSet controller for templated applications
- **dex**: Authentication service with OAuth/OIDC support
- **notification**: Notification controller for alerts and webhooks

### Security Features Applied
- **Base Image**: Red Hat UBI8 with FIPS-certified OpenSSL
- **Hardened Compilation**: Stack protection, FORTIFY_SOURCE, RELRO flags
- **Minimal Runtime**: Non-root execution, minimal attack surface
- **Patch Management**: Version-specific security patches in `patches/argocd/v3.0.11/`
- **VEX Statements**: Vulnerability exceptions in `vex/argocd/`

## Pipeline Features

### Matrix Builds
Automatically generates build jobs for each container defined in the project configuration. The GitHub Actions pipeline creates parallel jobs for:
- Building each component container
- Scanning each component independently  
- Testing FIPS compliance per component
- Generating component-specific artifacts

### Quality Gates
Each container must pass all quality gates before release:
- ✅ **Vulnerability Scanning**: No unmitigated HIGH/CRITICAL CVEs
- ✅ **FIPS Compliance**: OpenSSL FIPS mode verification
- ✅ **Component Testing**: Functionality and security tests
- ✅ **Hardening Checks**: Non-root execution, minimal dependencies

### Artifacts Generated
Per component artifacts include:
- **Container Image**: Tagged with project version (`mailknight/argocd-server:v3.0.11-mailknight`)
- **SBOM**: CycloneDX format Software Bill of Materials (`image-sbom-server.json`)
- **Scan Results**: Trivy vulnerability reports (`scan-results/server/`)
- **Test Results**: FIPS compliance and security test outputs (`test-results/server/`)
- **VEX Statements**: Applied vulnerability exceptions

## Usage

### Triggering Builds

**GitHub Actions:**
```bash
# Triggered automatically on push to paths:
# - projects/argocd/**
# - patches/argocd/**  
# - scripts/**

# Manual trigger via workflow dispatch
gh workflow run argocd.yml

# Or push changes to trigger build
git commit -m "Update ArgoCD server configuration"
git push origin main
```

### Local Development

```bash
# Build specific component
./scripts/build-container.sh argocd v3.0.11 server Dockerfile.server

# Scan specific component for vulnerabilities
./scripts/scan-image.sh argocd v3.0.11 server

# Test FIPS compliance for component
./scripts/test-fips-compliance.sh argocd v3.0.11 server

# Validate project configuration
./scripts/validate-config.sh
```

### Development Workflow

1. **Update Configuration**: Modify `projects/argocd/mailknight.yaml`
2. **Update Dockerfiles**: Modify component-specific Dockerfiles
3. **Test Locally**: Use script commands to test individual components
4. **Apply Patches**: Add security patches to `patches/argocd/v3.0.11/`
5. **Update VEX**: Document vulnerability exceptions in `vex/argocd/`
6. **Commit Changes**: Push to trigger CI/CD pipeline

### Example Output
```
📦 Built Images:
- mailknight/argocd-server:v3.0.11-mailknight
- mailknight/argocd-repo-server:v3.0.11-mailknight
- mailknight/argocd-application-controller:v3.0.11-mailknight
- mailknight/argocd-applicationset-controller:v3.0.11-mailknight
- mailknight/argocd-dex:v3.0.11-mailknight
- mailknight/argocd-notification:v3.0.11-mailknight

🔐 All components: FIPS-compliant ✅
🛡️  All components: No HIGH/CRITICAL CVEs ✅
📋 SBOMs: Generated for each component ✅
```

## Adding New Projects

### 1. Project Setup
Create the project structure:
```bash
mkdir -p projects/{project-name}
mkdir -p patches/{project-name}/common
mkdir -p patches/{project-name}/v{version}
mkdir -p vex/{project-name}
```

### 2. Project Configuration
Create `projects/{project-name}/mailknight.yaml`:
```yaml
apiVersion: v1
kind: MailknightProject
metadata:
  name: {project-name}
  description: "Project description"
spec:
  upstream:
    repository: "https://github.com/upstream/repo.git"
    version: "v1.0.0"
  
  settings:
    goVersion: "1.21"     # If Go project
    fipsEnabled: true
  
  containers:
    main:                 # At least one container required
      description: "Main component"
      dockerfile: "Dockerfile"
      entrypoint: "/usr/local/bin/app"
      dependencies:
        - ca-certificates
```

### 3. Dockerfiles
Create component-specific Dockerfiles:
- `Dockerfile` (base/main component)
- `Dockerfile.{component}` (additional components)

### 4. CI/CD Integration

**GitHub Actions:**
Create `.github/workflows/{project-name}.yml` based on `argocd.yml` template.

Update `.github/workflows/main.yml` to detect changes for the new project:
```yaml
# Add to detect-changes job outputs
{project-name}-changed: ${{ steps.changes.outputs.{project-name} }}

# Add to detect-changes job steps
if git diff --name-only HEAD~1 HEAD | \
   grep -E "(projects/{project-name}/|patches/{project-name}/|scripts/)" \
   > /dev/null; then
  echo "{project-name}=true" >> $GITHUB_OUTPUT
else
  echo "{project-name}=false" >> $GITHUB_OUTPUT
fi

# Add trigger job
trigger-{project-name}:
  needs: [validate-pipeline, detect-changes]
  if: needs.detect-changes.outputs.{project-name}-changed == 'true'
  uses: ./.github/workflows/{project-name}.yml
  secrets: inherit
```

### 5. Security Configuration
- Add patches to `patches/{project-name}/v{version}/`
- Create VEX statements in `vex/{project-name}/`
- Test FIPS compliance with project-specific tests

## Understanding CI Configuration

### GitHub Actions Pipeline

Mailknight uses GitHub Actions to provide comprehensive CI/CD automation with:

- **Workflow Orchestration**: Main workflow detects changes and triggers appropriate project builds
- **Matrix Builds**: Automatic parallel builds for multiple container components
- **Security Integration**: Built-in vulnerability scanning and compliance testing
- **Artifact Management**: Secure handling of build outputs and security reports

### Pipeline Features

GitHub Actions provides enterprise-grade features including:
- Container-based builds using Red Hat UBI8 for FIPS compliance
- Integrated security scanning with SARIF reporting
- Artifact retention and management
- Conditional workflows and dependency management

## Security Features

- **FIPS-140-2 Compliance**: OpenSSL FIPS mode enforced
- **Hardened Builds**: Stack protection, FORTIFY_SOURCE, RELRO, PIE
- **Minimal Runtime**: Non-root execution, minimal attack surface
- **Vulnerability Scanning**: Component-specific CVE detection
- **Supply Chain Security**: SBOM generation, artifact signing
- **VEX Support**: Component-specific vulnerability overrides

Mailknight ensures each container component meets the same high security standards while allowing for different build requirements and optimizations. The GitHub Actions pipeline provides enterprise-grade automation with comprehensive security scanning and compliance testing.