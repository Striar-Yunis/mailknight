# ArgoCD FIPS-Compliant Base Dockerfile
# Multi-stage build for minimal, hardened ArgoCD components

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
ARG GO_VERSION
RUN if [ -z "$GO_VERSION" ]; then \
        echo "Error: GO_VERSION build argument is required" && exit 1; \
    fi && \
    GO_FULL_VERSION="${GO_VERSION}.5" && \
    echo "Installing Go version ${GO_FULL_VERSION}" && \
    curl -L "https://golang.org/dl/go${GO_FULL_VERSION}.linux-amd64.tar.gz" | \
    tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:$PATH"

# Install Node.js with FIPS support
ARG NODE_VERSION
RUN if [ -z "$NODE_VERSION" ]; then \
        echo "Error: NODE_VERSION build argument is required" && exit 1; \
    fi && \
    echo "Installing Node.js version ${NODE_VERSION}" && \
    curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
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

# Build all ArgoCD components with hardening flags
RUN make build LDFLAGS="-linkmode external -extldflags '-static-pie -Wl,-z,relro,-z,now'" && \
    strip dist/argocd-* && \
    chmod 755 dist/argocd*

# Component-specific runtime stages will use this as base
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as runtime-base

# Install minimal runtime dependencies
RUN microdnf update -y && \
    microdnf install -y \
        ca-certificates \
        tzdata && \
    microdnf clean all

# Create non-root user
RUN groupadd -r argocd && \
    useradd -r -g argocd -s /bin/false argocd

# Create working directory
RUN mkdir -p /app && chown argocd:argocd /app
WORKDIR /app

# Enable FIPS mode
ENV OPENSSL_FORCE_FIPS_MODE=1

# Switch to non-root user
USER argocd

# This base image will be extended by component-specific Dockerfiles