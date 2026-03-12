#!/bin/bash
# ============================================================
#  Webhook Agent — Auto Setup Script
#  Run once on a fresh VPS after cloning this repo
#  Usage:  bash setup.sh
# ============================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
err()  { echo -e "${RED}[error]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Webhook Agent — VPS Setup           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Check .env exists ────────────────────────────────────
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        warn ".env not found — copying from .env.example"
        cp .env.example .env
        err "Please fill in .env first (VPS_TOKEN, BACKEND_API_URL, ENCRYPTION_KEY, PORT) then run setup.sh again"
    else
        err ".env file missing. Create it with PORT, VPS_TOKEN, BACKEND_API_URL, ENCRYPTION_KEY"
    fi
fi

# ── 2. Read PORT from .env ──────────────────────────────────
PORT=$(grep -E '^PORT=' .env | cut -d '=' -f2 | tr -d ' \r')
PORT=${PORT:-3000}
log "Using PORT=$PORT"

# ── 3. Check required .env values ──────────────────────────
VPS_TOKEN=$(grep -E '^VPS_TOKEN=' .env | cut -d '=' -f2 | tr -d ' \r')
BACKEND_API_URL=$(grep -E '^BACKEND_API_URL=' .env | cut -d '=' -f2 | tr -d ' \r')
ENCRYPTION_KEY=$(grep -E '^ENCRYPTION_KEY=' .env | cut -d '=' -f2 | tr -d ' \r')

[ -z "$VPS_TOKEN" ]      && err "VPS_TOKEN is empty in .env"
[ -z "$BACKEND_API_URL" ] && err "BACKEND_API_URL is empty in .env"
[ -z "$ENCRYPTION_KEY" ]  && err "ENCRYPTION_KEY is empty in .env"
[[ "$VPS_TOKEN" == *"PASTE"* ]] && err "VPS_TOKEN is still the placeholder — paste your real token"
[[ "$ENCRYPTION_KEY" == *"PASTE"* ]] && err "ENCRYPTION_KEY is still the placeholder — paste your real key"

log "All .env values look good"

# ── 4. Install Node.js if missing ──────────────────────────
if ! command -v node &>/dev/null; then
    log "Node.js not found — installing v20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    NODE_VER=$(node -v)
    log "Node.js already installed: $NODE_VER"
fi

# ── 5. npm install ──────────────────────────────────────────
log "Installing npm dependencies..."
npm install --omit=dev

# ── 6. Install PM2 if missing ───────────────────────────────
if ! command -v pm2 &>/dev/null; then
    log "Installing PM2 globally..."
    sudo npm install -g pm2
else
    log "PM2 already installed: $(pm2 -v)"
fi

# ── 7. Find free port if PORT is taken ─────────────────────
is_port_free() { ! ss -tlnp 2>/dev/null | grep -q ":$1 "; }

if ! is_port_free $PORT; then
    warn "Port $PORT is already in use — finding a free port..."
    for p in $(seq 3001 3099); do
        if is_port_free $p; then
            PORT=$p
            # Update .env
            sed -i "s/^PORT=.*/PORT=$PORT/" .env
            log "Assigned free port: $PORT (updated in .env)"
            break
        fi
    done
fi

# ── 8. Stop existing PM2 process if running ────────────────
pm2 delete webhook-agent 2>/dev/null || true

# ── 9. Start with PM2 ───────────────────────────────────────
log "Starting webhook-agent with PM2 on port $PORT..."
pm2 start webhook.js --name webhook-agent
pm2 save

# ── 10. Setup PM2 auto-start on reboot ─────────────────────
log "Configuring PM2 startup..."
pm2 startup | tail -1 | bash 2>/dev/null || warn "Run 'pm2 startup' manually if needed"

# ── 11. Setup nginx virtual host ───────────────────────────
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

if command -v nginx &>/dev/null; then
    log "Nginx found — creating virtual host..."

    NGINX_CONF="/etc/nginx/sites-available/webhook-agent"
    sudo bash -c "cat > $NGINX_CONF" << NGINXEOF
server {
    listen 80;
    server_name $SERVER_IP _;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }
}
NGINXEOF

    sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/webhook-agent 2>/dev/null || true
    sudo nginx -t && sudo systemctl reload nginx
    log "Nginx configured — webhook accessible at http://$SERVER_IP/deploy"
else
    warn "Nginx not installed — webhook accessible directly at http://$SERVER_IP:$PORT/deploy"
    warn "To install nginx: sudo apt-get install -y nginx"
fi

# ── 12. UFW firewall ────────────────────────────────────────
if command -v ufw &>/dev/null; then
    sudo ufw allow 80/tcp 2>/dev/null || true
    sudo ufw allow $PORT/tcp 2>/dev/null || true
fi

# ── Done ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup complete!                                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Webhook URL:  ${BLUE}http://$SERVER_IP/deploy${NC}"
echo -e "  Health check: ${BLUE}http://$SERVER_IP/health${NC}"
echo -e "  Direct port:  ${BLUE}http://$SERVER_IP:$PORT/deploy${NC}"
echo ""
echo -e "  PM2 status:   ${YELLOW}pm2 status${NC}"
echo -e "  Live logs:    ${YELLOW}pm2 logs webhook-agent${NC}"
echo ""
echo -e "  Add this Webhook URL in GitHub repo → Settings → Webhooks"
echo ""
