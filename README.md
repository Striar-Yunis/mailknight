# Mailknight

Mailknight is a secure software supply chain automation system that builds hardened, FIPS-compliant container images from open source projects. Inspired by Chainguard's approach, it provides end-to-end automation for secure container builds with comprehensive vulnerability scanning and compliance testing.

## 🏗️ Architecture

Mailknight supports **multi-container projects** where each component has optimized build configurations, security scanning, and FIPS compliance testing. The system runs on GitHub Actions, using Red Hat UBI8 base images for FIPS 140-2 compliance.

### Core Components

- **Projects**: Multi-container project definitions (`projects/argocd/`)
- **Patches**: Security patches and FIPS compliance fixes (`patches/argocd/`)
- **VEX Statements**: Vulnerability exception documentation (`vex/argocd/`)
- **Scripts**: Automation tools for building, scanning, and testing (`scripts/`)
- **GitHub Actions**: CI/CD workflows (`.github/workflows/`)

## 🔧 Key Features

### Multi-Container Support
- Individual Dockerfiles per component
- Component-specific dependency management
- Isolated security scanning and testing
- Per-component SBOM generation

### Security & Compliance
- **FIPS 140-2 Compliance**: OpenSSL FIPS mode enforced
- **Hardened Builds**: Stack protection, FORTIFY_SOURCE, RELRO, PIE
- **Vulnerability Scanning**: Trivy-based CVE detection with VEX overrides
- **Supply Chain Security**: SBOM generation and artifact signing preparation

### Automated Pipelines
- **Simplified & LLM-Friendly**: Streamlined from 10+ jobs to 4 core jobs
- **Copilot Integration**: Auto-runs when issues assigned to @copilot
- **Auto-Fix Requests**: Creates issues automatically on pipeline failures
- **GitHub Actions**: Comprehensive CI/CD automation with FIPS compliance
- **Matrix Builds**: Automatic multi-container builds (6 ArgoCD components)
- **Quality Gates**: Block releases on HIGH/CRITICAL CVEs
- **Reproducible Builds**: SOURCE_DATE_EPOCH and hardened build flags

## 📦 Example: ArgoCD Project

Mailknight builds 6 hardened ArgoCD containers:

| Component | Description | Key Dependencies |
|-----------|-------------|------------------|
| `server` | API Server | Git, SSH, CA certificates |
| `repo-server` | Repository Server | Git, Helm, Kustomize, GnuPG |
| `application-controller` | Main Controller | Minimal (CA certificates only) |
| `applicationset-controller` | ApplicationSet Controller | Minimal (CA certificates only) |
| `dex` | Authentication Service | Minimal (CA certificates only) |
| `notification` | Notification Controller | Minimal (CA certificates only) |

### Build Output
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

## 🚀 Quick Start

### Prerequisites
- GitHub Actions environment
- Access to Red Hat UBI8 base images
- Docker 24+ with BuildKit support

### Running a Build

**GitHub Actions:**
```bash
# Trigger via workflow dispatch or push to trigger paths
git push origin main

# Or trigger ArgoCD-specific workflow
gh workflow run argocd.yml

# Auto-trigger for copilot issues
# Simply assign any issue to @copilot for automated pipeline execution
```

**Pipeline Structure (Simplified):**
```yaml
Main Pipeline (main.yml):
  1. copilot-autorun      # Auto-trigger when issues assigned to @copilot
  2. build-and-validate   # Config validation + change detection
  3. argocd-build        # ArgoCD workflow (if changes detected)  
  4. request-fixes       # Auto-create fix requests on failures

ArgoCD Workflow (argocd.yml):
  1. build-all-components # Fetch + Patch + Build (consolidated)
  2. test-and-scan       # Security scan + FIPS test (matrix: 6 components)
  3. release             # Release artifacts (tags/manual only)
```

See [PIPELINE.md](PIPELINE.md) for detailed documentation.

### Local Development
```bash
# Build specific component
./scripts/build-container.sh argocd v3.0.11 server Dockerfile.server

# Scan for vulnerabilities
./scripts/scan-image.sh argocd v3.0.11 server

# Test FIPS compliance
./scripts/test-fips-compliance.sh argocd v3.0.11 server
```

## 📋 Project Structure

```
mailknight/
├── .github/workflows/          # GitHub Actions workflows
├── projects/
│   └── argocd/
│       ├── mailknight.yaml     # Project configuration
│       └── Dockerfile.*        # Component Dockerfiles
├── patches/argocd/             # Security patches per version
├── vex/argocd/                 # VEX vulnerability statements
└── scripts/                    # Build automation scripts
```

## 🛡️ Security Pipeline

Each container goes through:

1. **Source Preparation** (shared)
   - Fetch upstream source
   - Apply security patches
   - Build all binaries with hardened flags

2. **Container Building** (per component)
   - Component-specific Dockerfiles
   - Minimal runtime dependencies
   - FIPS-compliant base images

3. **Security Scanning** (per component)
   - Trivy vulnerability scanning
   - VEX statement application
   - SBOM generation

4. **FIPS Testing** (per component)
   - Runtime FIPS verification
   - Component functionality tests
   - Security hardening checks

## 🔧 Configuration

### Project Configuration (`mailknight.yaml`)
```yaml
apiVersion: v1
kind: MailknightProject
metadata:
  name: argocd
spec:
  upstream:
    repository: "https://github.com/argoproj/argo-cd.git"
    version: "v3.0.11"
  
  containers:
    server:
      dockerfile: "Dockerfile.server"
      entrypoint: "/usr/local/bin/argocd-server"
      dependencies: [git, ca-certificates, openssh-client]
```

### Hardening Flags
```bash
CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -O2"
LDFLAGS="-Wl,-z,relro,-z,now -pie"
OPENSSL_FORCE_FIPS_MODE=1
```

## 🎯 Planned Projects

Future projects to support:
- **crossplane**: Cloud infrastructure management
- **cert-manager**: Certificate management
- **vault**: Secrets management
- **nginx**: FIPS-compliant reverse proxy

## 🤝 Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed development guide, including:
- Adding new projects
- Creating patches
- VEX statement management
- Testing procedures

## 📄 License

This project builds hardened versions of open source software. Each upstream project maintains its own license. Mailknight's build automation and patches are available under the Apache 2.0 license.