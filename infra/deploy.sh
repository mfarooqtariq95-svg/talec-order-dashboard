#!/usr/bin/env bash
# Deploy the order-dashboard's static files into the talec-orders API box's
# dashboard/ subtree — talec-command-center's shared Caddy file_servers that
# path for orders.talec.pk (see the orders.talec.pk block in
# apps/talec-command-center/infra/Caddyfile). This repo owns that subtree
# exclusively; the whatsapp-api deploy.sh explicitly excludes it so the two
# deploys never fight over it.
#
# Usage: ./deploy.sh [user@host]   (defaults to talec@159.69.176.8)

set -euo pipefail

TARGET="${1:-talec@159.69.176.8}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/talec_vps}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # apps/order-dashboard

SSH="ssh -i $SSH_KEY"

echo "==> Deploying $APP_ROOT -> $TARGET:/opt/talec-orders/dashboard"

$SSH "$TARGET" "mkdir -p /opt/talec-orders/dashboard"

rsync -avz --delete \
  -e "$SSH" \
  --exclude '.git' --exclude 'infra' --exclude '.DS_Store' --exclude 'README.md' \
  "$APP_ROOT/" "$TARGET:/opt/talec-orders/dashboard/"

echo "==> Done. Caddy serves this directly, no restart needed."
echo "==> Verify: curl -s https://orders.talec.pk/ | head -5"
