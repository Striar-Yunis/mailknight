#!/bin/sh
# ArgoCD application controller health check
exec /usr/local/bin/argocd version --client 2>/dev/null || exit 1