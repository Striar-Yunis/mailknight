# Secure Runtime Base Container
# Minimal, hardened base container for running applications
# Based on UBI minimal with security hardening

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

LABEL name="mailknight/runtime-base" \
      description="Minimal FIPS-compliant runtime environment" \
      vendor="Mailknight" \
      security.fips="enabled" \
      security.hardened="true" \
      org.opencontainers.image.source="https://github.com/Striar-Yunis/mailknight"

# Install minimal runtime dependencies
RUN microdnf update -y && \
    microdnf install -y \
        ca-certificates \
        tzdata \
        openssl \
        && \
    microdnf clean all

# Create non-root user for security
ARG USER_ID=999
ARG GROUP_ID=999
ARG USERNAME=appuser
ARG GROUPNAME=appuser

RUN groupadd -g ${GROUP_ID} ${GROUPNAME} && \
    useradd -r -u ${USER_ID} -g ${GROUPNAME} -s /bin/false -d /app ${USERNAME}

# Create application directory
RUN mkdir -p /app && \
    chown ${USERNAME}:${GROUPNAME} /app

# Enable FIPS mode for runtime
ENV OPENSSL_FORCE_FIPS_MODE=1

# Security hardening - drop capabilities, non-root user
USER ${USERNAME}
WORKDIR /app

# Health check helper script
COPY health-check.sh /usr/local/bin/health-check

# Make health check executable
USER root
RUN chmod +x /usr/local/bin/health-check
USER ${USERNAME}

# Default health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD ["/usr/local/bin/health-check"]

# Security labels and metadata
LABEL security.scan.enabled="true" \
      security.fips.validated="true" \
      security.user.nonroot="true" \
      maintenance.automated="true"

# Default command (to be overridden by specific applications)
CMD ["/bin/sh", "-c", "echo 'This is a base runtime container. Please specify an application command.'"]