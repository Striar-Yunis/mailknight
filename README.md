Mailknight is a secure software supply chain automation system, inspired by Chainguard. Its goal is to build hardened, FIPS-compliant container images and binary artifacts from open source projects like ArgoCD, Crossplane, cert-manager, etc., and keep them free of known CVEs using automation.

🔧 Key Features
Secure, reproducible GitLab CI pipelines

Use GitLab CI for fully automated, deterministic builds of open source projects

Ensure each pipeline can run:

On a FIPS-enabled base image (e.g., ubi8-minimal, rockylinux:8)

With hardened compiler flags (e.g., -fstack-protector, -D_FORTIFY_SOURCE=2, -Wl,-z,relro,-z,now)

With SBOM (Software Bill of Materials) generation

Use GitLab CI’s rules, needs, and artifacts for efficient builds and caching

FIPS-compliant builds

Compile binaries with OpenSSL FIPS modules where applicable

Enforce use of --openssl-fips or equivalent when building Node.js, Python, or other interpreted language runtimes

In containers, enable /proc/sys/crypto/fips_enabled or require runtime checks to ensure FIPS enforcement

Long-Term Support (LTS) downstreaming

Mirror and track upstream open source releases into a local Git monorepo

Patch upstream releases to remove CVEs using:

Git patches

Dependency overrides

Build flag adjustments

Maintain a patchset folder per project (like mailknight/patches/argocd/v2.11.0)

Use Git tags or GitLab Releases to track Mailknight downstream LTS builds

CVE scanning and VEX

Automatically scan all images with Trivy or Grype post-build

Output JSON results, and:

Block releases if HIGH or CRITICAL CVEs are present and not mitigated

Allow VEX (Vulnerability Exploitability eXchange) overrides for acceptable CVEs (e.g., package present but not used)

Store VEX justifications per CVE/project in JSON or markdown (mailknight/vex/argocd/2025-001.json)

Image hardening

Strip containers to minimal runtime base (scratch, distroless, ubi8-minimal)

Remove unused tools (e.g., jq, perl, wget, curl) from builds

Run strip, upx, and chmod -x on everything non-essential

Sign all images using cosign or sigstore

Automated downstream sync

Poll upstream GitHub releases via cron or webhook

When a new upstream release is tagged:

Automatically clone, diff against current LTS fork

Attempt to apply existing patches or flag merge conflicts

Rebuild and test using existing Mailknight pipeline

📦 Projects to Build FIPS-Compliant:
Example open source projects to support:

argocd

crossplane

cert-manager

vault

node (runtime)

python (runtime)

openssl (library builds)

nginx (reverse proxy with FIPS TLS)

💡 GitLab CI Best Practices
Use separate jobs for fetch-source, apply-patches, build, scan, and release

Use a GitLab CI template like .mailknight.yml to standardize across projects

Use GitLab's includes: to share pipelines across repos

Implement caching for source tarballs and build outputs

Tag artifacts with git hash + semantic version (e.g., mailknight-argocd:v2.11.0-lts.20250701)

Use git describe --tags to derive build version automatically

🧪 CI Quality Gates
FIPS enforcement test:

bash
Copy
Edit
test "$(cat /proc/sys/crypto/fips_enabled)" -eq 1
node -p "require('crypto').fips"
openssl version | grep -i fips
CVE scanning gate:

bash
Copy
Edit
trivy image --format json myimage | jq '.Results[].Vulnerabilities[] | select(.Severity=="HIGH" or .Severity=="CRITICAL")'
SBOM generation:

bash
Copy
Edit
syft dir:. -o cyclonedx-json > sbom.json
🧱 Future Stretch Goals
Cosign-based image signing

Sigstore keyless signing from GitLab CI

Rebuilderd-style reproducible build verifier

In-toto attestations

OCI-compatible release index (mailknight-index.json)
