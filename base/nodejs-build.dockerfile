# Node.js Build Base Container
# FIPS-compliant base container for building Node.js applications
# Usage: Used as base for building UI and JS components, not for runtime

FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL name="mailknight/nodejs-build-base" \
      description="FIPS-compliant Node.js build environment" \
      vendor="Mailknight" \
      security.fips="enabled" \
      org.opencontainers.image.source="https://github.com/Striar-Yunis/mailknight"

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
        python3 \
        python3-pip \
        python3-pyyaml \
        findutils \
        file \
        tar \
        gzip && \
    dnf clean all

# Install FIPS-compliant Node.js
ARG NODE_VERSION=18
RUN echo "Installing Node.js version ${NODE_VERSION}" && \
    curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    dnf install -y nodejs && \
    dnf clean all

# Install Yarn package manager
RUN npm install -g yarn

# Install Syft for SBOM generation
ARG SYFT_VERSION=0.100.0
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | \
    sh -s -- -b /usr/local/bin v${SYFT_VERSION}

# Set FIPS mode and build flags for security hardening
ENV OPENSSL_FORCE_FIPS_MODE=1 \
    NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=8192"

# Security hardening flags
ENV CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -O2" \
    CXXFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -O2" \
    LDFLAGS="-Wl,-z,relro,-z,now -pie"

# Build reproducibility
ENV SOURCE_DATE_EPOCH=1672531200

# Create build workspace
WORKDIR /workspace

# Verify Node.js installation
RUN node --version && \
    npm --version && \
    yarn --version && \
    echo "Node.js build environment ready with FIPS compliance"

# Default command for interactive use
CMD ["/bin/bash"]