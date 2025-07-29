# ArgoCD Binary Builder Dockerfile
# Builds ArgoCD binaries using secure base containers
# This stage only builds binaries - runtime containers are separate

# ==============================================================================
# Stage 1: Build UI components using Node.js build base
# ==============================================================================
FROM mailknight/nodejs-build-base:latest as ui-builder

# Copy UI source code
COPY source/ui/ /workspace/ui/
WORKDIR /workspace/ui

# Build ArgoCD UI with FIPS compliance
ARG ARGO_VERSION=latest
ENV ARGO_VERSION=$ARGO_VERSION
ARG TARGETARCH=amd64
ENV NODE_ENV=production
ENV NODE_ONLINE_ENV=online

# Install dependencies and build UI
RUN yarn install --network-timeout 200000 && \
    yarn cache clean && \
    HOST_ARCH=$TARGETARCH NODE_OPTIONS=--max_old_space_size=8192 yarn build

# ==============================================================================  
# Stage 2: Build Go binaries using Golang build base
# ==============================================================================
FROM mailknight/golang-build-base:latest as go-builder

# Copy Go source code
COPY source/ /workspace/
WORKDIR /workspace

# Copy UI build artifacts from previous stage
COPY --from=ui-builder /workspace/ui/dist/app /workspace/ui/dist/app

# Download Go dependencies
COPY source/go.* ./
RUN go mod download

# Build all ArgoCD components with hardening flags
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG GIT_TAG
ARG BUILD_DATE
ARG GIT_TREE_STATE
ARG GIT_COMMIT

# Set build-time variables
ENV BUILD_DATE=${BUILD_DATE:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}
ENV GIT_COMMIT=${GIT_COMMIT:-$(git rev-parse --short HEAD)}
ENV GIT_TAG=${GIT_TAG:-unknown}
ENV GIT_TREE_STATE=${GIT_TREE_STATE:-clean}

# Build with security hardening
RUN GIT_COMMIT=$GIT_COMMIT \
    GIT_TREE_STATE=$GIT_TREE_STATE \
    GIT_TAG=$GIT_TAG \
    BUILD_DATE=$BUILD_DATE \
    GOOS=$TARGETOS \
    GOARCH=$TARGETARCH \
    make argocd-all

# Strip binaries and set permissions for security
RUN strip dist/argocd* && \
    chmod 755 dist/argocd*

# Generate SBOM for the built binaries  
RUN syft dir:/workspace -o cyclonedx-json > /workspace/sbom.json

# ==============================================================================
# Final stage: Prepare build artifacts for consumption
# ==============================================================================
FROM scratch as artifacts

# Copy all built artifacts
COPY --from=go-builder /workspace/dist/ /binaries/
COPY --from=go-builder /workspace/sbom.json /sbom.json
COPY --from=ui-builder /workspace/ui/dist/app /ui/

# This stage is used to extract artifacts, not run as a container