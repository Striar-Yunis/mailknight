# Mailknight Development Guide

Mailknight is a secure software supply chain automation system that builds FIPS-compliant, hardened container images for open source projects.

## Architecture

### Multi-Container Project Support

Mailknight supports projects that consist of multiple containers with different build requirements. Each container can have:

- **Individual Dockerfiles**: Component-specific build configurations
- **Separate Dependencies**: Different runtime and build dependencies
- **Independent Scanning**: Vulnerability scanning per container
- **Component Testing**: FIPS compliance testing per container
- **Isolated Artifacts**: Separate SBOMs, scan results, and test reports

### Project Configuration

Each project defines its containers in a `mailknight.yaml` configuration file:

```yaml
apiVersion: v1
kind: MailknightProject
metadata:
  name: argocd
spec:
  upstream:
    repository: "https://github.com/argoproj/argo-cd.git"
    version: "v2.11.0"
  
  containers:
    server:
      description: "ArgoCD API Server"
      dockerfile: "Dockerfile.server"
      entrypoint: "/usr/local/bin/argocd-server"
      ports: [8080, 8083]
      dependencies:
        - git
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
├── .gitlab-ci.yml              # Main pipeline orchestration
├── .mailknight.yml             # Shared CI templates
├── projects/
│   └── argocd/
│       ├── mailknight.yaml     # Project configuration
│       ├── Dockerfile          # Base Dockerfile
│       ├── Dockerfile.server   # Server component
│       ├── Dockerfile.repo-server # Repository server
│       └── .gitlab-ci.yml      # Project pipeline
├── patches/argocd/             # Security patches
├── vex/argocd/                 # VEX statements
└── scripts/                    # Build automation
```

## Build Process

### 1. Source Preparation (Shared)
- Fetch upstream source code
- Apply security patches
- Build all binaries

### 2. Container Building (Per Component)
- Use component-specific Dockerfiles
- Install component-specific dependencies
- Generate component SBOMs

### 3. Security Scanning (Per Component)
- Vulnerability scanning with Trivy
- Component-specific VEX application
- Secret scanning

### 4. FIPS Testing (Per Component)
- Component-specific functionality tests
- FIPS mode verification
- Runtime security checks

## ArgoCD Example

The ArgoCD project demonstrates multi-container support with these components:

- **server**: API server with Git and SSH tools
- **repo-server**: Repository server with Git, Helm, and Kustomize
- **application-controller**: Main controller with minimal dependencies
- **applicationset-controller**: ApplicationSet controller
- **dex**: Authentication service
- **notification**: Notification controller

Each component:
- Has its own optimized Dockerfile
- Gets scanned independently
- Has component-specific tests
- Produces separate artifacts

## Pipeline Features

### Matrix Builds
Automatically generates build jobs for each container defined in the project configuration.

### Quality Gates
Each container must pass:
- ✅ Vulnerability scanning (HIGH/CRITICAL blocking)
- ✅ FIPS compliance verification
- ✅ Component functionality tests
- ✅ Container security hardening checks

### Artifacts
Per component:
- Container image (`.tar.gz`)
- SBOM (`image-sbom-{component}.json`)
- Scan results (`scan-results/{component}/`)
- Test results (`test-results/{component}/`)

## Usage

### Trigger Multi-Container Build
```bash
git commit --allow-empty -m "Build ArgoCD containers"
git push origin main
```

### Local Development
```bash
# Build specific component
./scripts/build-container.sh argocd v2.11.0 server Dockerfile.server

# Scan specific component
./scripts/scan-image.sh argocd v2.11.0 server

# Test specific component
./scripts/test-fips-compliance.sh argocd v2.11.0 server
```

### Example Output
```
📦 Built Images:
- mailknight/argocd-server:v2.11.0-mailknight
- mailknight/argocd-repo-server:v2.11.0-mailknight
- mailknight/argocd-application-controller:v2.11.0-mailknight
- mailknight/argocd-applicationset-controller:v2.11.0-mailknight
- mailknight/argocd-dex:v2.11.0-mailknight
- mailknight/argocd-notification:v2.11.0-mailknight

🔐 All components: FIPS-compliant ✅
🛡️  All components: No HIGH/CRITICAL CVEs ✅
📋 SBOMs: Generated for each component ✅
```

## Adding New Projects

1. Create project directory: `projects/{project-name}/`
2. Add `mailknight.yaml` configuration
3. Create base `Dockerfile` and component-specific Dockerfiles
4. Add project pipeline: `projects/{project-name}/.gitlab-ci.yml`
5. Configure patches: `patches/{project-name}/`

## Security Features

- **FIPS-140-2 Compliance**: OpenSSL FIPS mode enforced
- **Hardened Builds**: Stack protection, FORTIFY_SOURCE, RELRO, PIE
- **Minimal Runtime**: Non-root execution, minimal attack surface
- **Vulnerability Scanning**: Component-specific CVE detection
- **Supply Chain Security**: SBOM generation, artifact signing
- **VEX Support**: Component-specific vulnerability overrides

Mailknight ensures each container component meets the same high security standards while allowing for different build requirements and optimizations.