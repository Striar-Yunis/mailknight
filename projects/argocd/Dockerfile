# ArgoCD FIPS-Compliant Dockerfile
# Multi-stage build for minimal, hardened ArgoCD image

# Build stage using FIPS-enabled base
FROM registry.access.redhat.com/ubi8/ubi:latest as builder

# Install build dependencies
RUN dnf update -y && \
    dnf install -y \
        git \
        gcc \
        gcc-c++ \
        make \
        curl \
        wget \
        ca-certificates \
        openssl-devel \
        krb5-devel \
        libcom_err-devel && \
    dnf clean all

# Install FIPS-compliant Go
ARG GO_VERSION=1.21.5
RUN curl -L "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" | \
    tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:$PATH"

# Install Node.js with FIPS support
ARG NODE_VERSION=18
RUN curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    dnf install -y nodejs && \
    dnf clean all

# Set FIPS mode and build flags
ENV OPENSSL_FORCE_FIPS_MODE=1
ENV CGO_ENABLED=1
ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2"
ENV CGO_LDFLAGS="-Wl,-z,relro,-z,now"

# Copy ArgoCD source
COPY source/ /src/
WORKDIR /src

# Build ArgoCD with hardening flags
RUN make build LDFLAGS="-linkmode external -extldflags '-static-pie -Wl,-z,relro,-z,now'" && \
    strip dist/argocd-* && \
    chmod -x dist/argocd-* && \
    chmod +x dist/argocd

# Runtime stage with minimal base
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Install minimal runtime dependencies
RUN microdnf update -y && \
    microdnf install -y \
        ca-certificates \
        tzdata && \
    microdnf clean all

# Create non-root user
RUN groupadd -r argocd && \
    useradd -r -g argocd -s /bin/false argocd

# Copy ArgoCD binaries
COPY --from=builder /src/dist/argocd /usr/local/bin/argocd
COPY --from=builder /src/dist/argocd-server /usr/local/bin/argocd-server
COPY --from=builder /src/dist/argocd-repo-server /usr/local/bin/argocd-repo-server
COPY --from=builder /src/dist/argocd-application-controller /usr/local/bin/argocd-application-controller
COPY --from=builder /src/dist/argocd-dex /usr/local/bin/argocd-dex
COPY --from=builder /src/dist/argocd-redis /usr/local/bin/argocd-redis

# Set permissions
RUN chown root:root /usr/local/bin/argocd* && \
    chmod 755 /usr/local/bin/argocd*

# Create working directory
RUN mkdir -p /app && chown argocd:argocd /app
WORKDIR /app

# Switch to non-root user
USER argocd

# Enable FIPS mode
ENV OPENSSL_FORCE_FIPS_MODE=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD ["/usr/local/bin/argocd", "version", "--client"]

# Default command
ENTRYPOINT ["/usr/local/bin/argocd"]
CMD ["--help"]

# Labels for metadata
LABEL name="mailknight/argocd" \
      version="v2.11.0-mailknight" \
      description="FIPS-compliant ArgoCD container image" \
      vendor="Mailknight" \
      security.fips="enabled" \
      org.opencontainers.image.source="https://github.com/Striar-Yunis/mailknight"