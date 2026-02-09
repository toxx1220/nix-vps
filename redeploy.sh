#!/usr/bin/env bash
set -euo pipefail

# Ensure we only run this logic on the main branch
if [ "${GARNIX_BRANCH:-}" != "main" ]; then
  echo "Not on main branch (GARNIX_BRANCH=${GARNIX_BRANCH:-}). Skipping webhook."
  exit 0
fi

echo "Decrypting webhook secret..."
WEBHOOK_SECRET=$(age -d -i "$GARNIX_ACTION_PRIVATE_KEY_FILE" webhook-secret.age)

echo "Calculating signature..."
PAYLOAD='{}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/^.* //')

echo "Triggering redeploy webhook..."
curl -v -X POST https://deploy.toxx.dev/hooks/redeploy \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -d "$PAYLOAD"
