#!/usr/bin/env bash
# Example healthcheck for the template tool.
# Contract: exit 0 = healthy, non-zero = unhealthy. Print one status line.
set -euo pipefail

if curl -fsS --max-time 3 "http://_template:8000/health" >/dev/null 2>&1; then
  echo "template tool: OK"
  exit 0
else
  echo "template tool: not reachable"
  exit 1
fi
