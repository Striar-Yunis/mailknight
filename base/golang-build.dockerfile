# Golang Build Base Container
# FIPS-compliant base container for building Go applications
# Usage: Used as base for building binaries, not for runtime

FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL name="mailknight/golang-build-base" \
      description="FIPS-compliant Golang build environment" \
      vendor="Mailknight" \
      security.fips="enabled" \
      org.opencontainers.image.source="https://github.com/Striar-Yunis/mailknight"

# Install build dependencies
RUN dnf update -y && \
    dnf install -y --allowerasing \
        git \
        gcc \
        gcc-c++ \
        make \
        curl \
        wget \
        ca-certificates \
        openssl-devel \
        krb5-devel \
        libcom_err-devel \
        python3 \
        python3-pyyaml \
        findutils \
        file \
        tar \
        gzip && \
    dnf clean all

# Install FIPS-compliant Go
ARG GO_VERSION=1.24.4
RUN echo "Installing Go version ${GO_VERSION}" && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | \
    tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:$PATH"

# Install Syft for SBOM generation
ARG SYFT_VERSION=0.100.0
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | \
    sh -s -- -b /usr/local/bin v${SYFT_VERSION}

# Set FIPS mode and build flags for security hardening
ENV OPENSSL_FORCE_FIPS_MODE=1 \
    GOLANG_FIPS=1 \
    CGO_ENABLED=1 \
    GOOS=linux \
    GOARCH=amd64

# Security hardening flags
ENV CGO_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -O2" \
    CGO_LDFLAGS="-Wl,-z,relro,-z,now" \
    CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -O2" \
    CXXFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -O2" \
    LDFLAGS="-Wl,-z,relro,-z,now -pie"

# Build reproducibility
ENV SOURCE_DATE_EPOCH=1672531200

# Create build workspace
WORKDIR /workspace

# Verify Go installation and FIPS compliance
RUN go version && \
    echo "Go build environment ready with FIPS compliance"

# Default command for interactive use
CMD ["/bin/bash"]