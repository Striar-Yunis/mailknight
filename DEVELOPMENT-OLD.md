# Mailknight Development Guide

## Overview

Mailknight is a secure software supply chain automation system that builds hardened, FIPS-compliant container images and binary artifacts from open source projects.

## Quick Start

### Building ArgoCD

```bash
# Trigger ArgoCD build pipeline
git commit --allow-empty -m "Trigger ArgoCD build"
git push origin main
```

### Local Development

```bash
# Validate configuration
./scripts/validate-config.sh

# Fetch ArgoCD source
./scripts/fetch-upstream.sh argocd v2.11.0

# Apply patches
./scripts/apply-patches.sh argocd v2.11.0

# Build binary
./scripts/build-project.sh argocd

# Build container (requires Docker)
./scripts/build-container.sh argocd v2.11.0

# Run security scans
./scripts/install-trivy.sh
./scripts/scan-image.sh argocd v2.11.0

# Test FIPS compliance
./scripts/test-fips-compliance.sh argocd v2.11.0

# Create release
./scripts/release-artifacts.sh argocd v2.11.0
```

## Directory Structure

```
mailknight/
├── .gitlab-ci.yml           # Main GitLab CI pipeline
├── .mailknight.yml          # Shared CI templates
├── projects/                # Project-specific configurations
│   └── argocd/
│       ├── .gitlab-ci.yml   # ArgoCD pipeline
│       └── Dockerfile       # FIPS-compliant Dockerfile
├── patches/                 # Security and FIPS patches
│   └── argocd/
│       ├── v2.11.0/         # Version-specific patches
│       └── common/          # Common patches
├── vex/                     # VEX (Vulnerability Exploitability eXchange)
│   └── argocd/
│       └── 2025-001.json    # VEX statements
├── scripts/                 # Build and automation scripts
└── README.md                # This file
```

## Adding New Projects

1. Create project directory: `mkdir -p projects/newproject`
2. Add GitLab CI configuration: `projects/newproject/.gitlab-ci.yml`
3. Create Dockerfile: `projects/newproject/Dockerfile`
4. Add patches directory: `mkdir -p patches/newproject/common`
5. Update main pipeline to trigger new project

## Security Features

### FIPS Compliance
- Uses FIPS-enabled base images (UBI8)
- Compiles with FIPS-compliant OpenSSL
- Enables FIPS mode in runtime environment
- Tests FIPS compliance in CI pipeline

### Hardening
- Stack protection (`-fstack-protector-strong`)
- FORTIFY_SOURCE (`-D_FORTIFY_SOURCE=2`)
- RELRO (`-Wl,-z,relro,-z,now`)
- Position Independent Executables (PIE)
- Minimal runtime environment
- Non-root execution

### Supply Chain Security
- Source code verification
- Dependency scanning with Trivy
- SBOM generation with Syft
- VEX statements for vulnerability management
- Artifact signing with Cosign

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FIPS_ENABLED` | Enable FIPS mode | `true` |
| `TRIVY_VERSION` | Trivy scanner version | `0.48.0` |
| `SYFT_VERSION` | Syft SBOM generator version | `0.100.0` |
| `COSIGN_VERSION` | Cosign signing tool version | `2.2.2` |

### Build Flags

| Flag | Purpose |
|------|---------|
| `CFLAGS` | C compiler hardening flags |
| `CXXFLAGS` | C++ compiler hardening flags |
| `LDFLAGS` | Linker hardening flags |
| `CGO_CFLAGS` | CGO C compiler flags |
| `CGO_LDFLAGS` | CGO linker flags |

## Quality Gates

The pipeline includes several quality gates:

1. **Configuration Validation**: Validates YAML syntax and directory structure
2. **Source Verification**: Verifies source code integrity and signatures
3. **FIPS Compliance**: Tests FIPS mode and cryptographic compliance
4. **Vulnerability Scanning**: Scans for HIGH and CRITICAL CVEs
5. **Supply Chain Security**: Generates and validates SBOMs

## Troubleshooting

### Common Issues

**FIPS Mode Not Enabled**
- Ensure base image supports FIPS
- Check `OPENSSL_FORCE_FIPS_MODE=1` environment variable
- Verify `/proc/sys/crypto/fips_enabled` is set to 1

**Build Failures**
- Check hardening flags compatibility
- Verify all dependencies support static linking
- Review patch application logs

**Security Scan Failures**
- Review VEX statements in `vex/` directory
- Update base image to latest security patches
- Apply project-specific security patches

### Debug Mode

Enable debug output in scripts:
```bash
export DEBUG=1
./scripts/build-project.sh argocd
```

## Contributing

1. Add new projects following the existing structure
2. Include security patches in appropriate directories
3. Update documentation for new features
4. Test FIPS compliance for all changes

## Support

For questions and support:
- Review logs in GitLab CI pipeline
- Check script output in debug mode
- Verify configuration with validation script