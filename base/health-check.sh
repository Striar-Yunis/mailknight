#!/bin/sh
# Generic health check script
# Override in specific containers as needed
if [ -f "/app/health" ]; then
    exec /app/health "$@"
else
    echo "Health check not configured for this application"
    exit 0
fi