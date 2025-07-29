#!/bin/sh
# ArgoCD server health check
exec /usr/local/bin/argocd admin settings rbac can get applications --server localhost:8080 --plaintext --insecure 2>/dev/null || exit 1