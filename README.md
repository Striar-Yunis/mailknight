# Mailknight

Mailknight is a secure software supply chain automation system that builds hardened, FIPS-compliant container images from open source projects. Inspired by Chainguard's approach, it provides end-to-end automation for secure container builds with comprehensive vulnerability scanning and compliance testing.

## 🏗️ Architecture

Mailknight supports **multi-container projects** where each component has optimized build configurations, security scanning, and FIPS compliance testing. The system runs on both GitLab CI and GitHub Actions, using Red Hat UBI8 base images for FIPS 140-2 compliance.

### Core Components

- **Projects**: Multi-container project definitions (`projects/argocd/`)
- **Patches**: Security patches and FIPS compliance fixes (`patches/argocd/`)
- **VEX Statements**: Vulnerability exception documentation (`vex/argocd/`)
- **Scripts**: Automation tools for building, scanning, and testing (`scripts/`)
- **CI Templates**: Shared pipeline templates (`.mailknight.yml`)

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
- **GitLab CI & GitHub Actions**: Dual CI support for flexibility
- **Matrix Builds**: Automatic multi-container builds
- **Quality Gates**: Block releases on HIGH/CRITICAL CVEs
- **Reproducible Builds**: SOURCE_DATE_EPOCH and build flags

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
- GitLab CI runner with Docker support OR GitHub Actions environment
- Access to Red Hat UBI8 base images
- Docker 24+ with BuildKit support

### Running a Build

**GitLab CI:**
```bash
# Trigger ArgoCD multi-container build
git commit --allow-empty -m "Build ArgoCD containers"
git push origin main
```

**GitHub Actions:**
```bash
# Trigger via workflow dispatch or push to trigger paths
git push origin main
```

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
├── .gitlab-ci.yml              # GitLab CI orchestration
├── .github/workflows/          # GitHub Actions workflows
├── .mailknight.yml             # Shared CI templates
├── projects/
│   └── argocd/
│       ├── mailknight.yaml     # Project configuration
│       ├── Dockerfile.*        # Component Dockerfiles
│       └── .gitlab-ci.yml      # Project-specific pipeline
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