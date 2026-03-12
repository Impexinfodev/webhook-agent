#!/bin/bash
# ============================================================
#  Webhook Agent — Full Install Script
#  Run on a fresh VPS:  bash <(curl -s URL/install.sh)
#  OR after cloning:    bash install.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}   $1"; }
err()  { echo -e "${RED}[error]${NC}  $1"; exit 1; }
info() { echo -e "${BLUE}[info]${NC}   $1"; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Webhook Agent — VPS Install                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Clone repo if not already cloned ─────────────────────
INSTALL_DIR="/opt/webhook-agent"

if [ ! -d "$INSTALL_DIR" ]; then
    log "Cloning webhook-agent to $INSTALL_DIR..."
    git clone https://github.com/Impexinfodev/webhook-agent.git "$INSTALL_DIR" || err "Git clone failed. Check the repo URL."
else
    log "Directory $INSTALL_DIR already exists — pulling latest..."
    cd "$INSTALL_DIR" && git pull
fi

cd "$INSTALL_DIR"

# ── 2. Show free ports (3000–3099) ──────────────────────────
echo ""
echo -e "${BLUE}── Free ports in range 3000–3099 ──────────────────────${NC}"

FREE_PORTS=()
for p in $(seq 3000 3099); do
    if ! ss -tlnp 2>/dev/null | grep -q ":$p "; then
        FREE_PORTS+=($p)
    fi
done

if [ ${#FREE_PORTS[@]} -eq 0 ]; then
    err "No free ports found in range 3000–3099!"
fi

# Show first 10 free ports
echo -e "${GREEN}Free ports:${NC} ${FREE_PORTS[@]:0:10} ..."
SUGGESTED_PORT=${FREE_PORTS[0]}
echo ""
echo -e "${YELLOW}Suggested port: $SUGGESTED_PORT${NC}"
echo ""

# ── 3. Create .env if not exists ────────────────────────────
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        log "Created .env from .env.example"
    else
        err ".env.example not found in repo"
    fi
fi

# Auto-set the suggested port in .env
sed -i "s/^PORT=.*/PORT=$SUGGESTED_PORT/" .env
log "Set PORT=$SUGGESTED_PORT in .env"

# ── 4. Open .env for editing ────────────────────────────────
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Now fill in your .env values:                       ║${NC}"
echo -e "${YELLOW}║                                                      ║${NC}"
echo -e "${YELLOW}║  VPS_TOKEN      → CRM UI se copy karo                ║${NC}"
echo -e "${YELLOW}║  BACKEND_API_URL→ https://api.webhook.aashita.ai     ║${NC}"
echo -e "${YELLOW}║  ENCRYPTION_KEY → backend .env wali same key         ║${NC}"
echo -e "${YELLOW}║  PORT           → $SUGGESTED_PORT (already set)               ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -p "Press ENTER to open .env in nano editor..."
nano .env

# ── 5. Validate .env ────────────────────────────────────────
VPS_TOKEN=$(grep -E '^VPS_TOKEN=' .env | cut -d '=' -f2 | tr -d ' \r')
BACKEND_API_URL=$(grep -E '^BACKEND_API_URL=' .env | cut -d '=' -f2 | tr -d ' \r')
ENCRYPTION_KEY=$(grep -E '^ENCRYPTION_KEY=' .env | cut -d '=' -f2 | tr -d ' \r')

[ -z "$VPS_TOKEN" ]       && err "VPS_TOKEN is empty in .env"
[ -z "$BACKEND_API_URL" ] && err "BACKEND_API_URL is empty in .env"
[ -z "$ENCRYPTION_KEY" ]  && err "ENCRYPTION_KEY is empty in .env"
[[ "$VPS_TOKEN" == *"PASTE"* ]] && err "VPS_TOKEN is still the placeholder — paste your real token"

log "All .env values look good"

# ── 6. Run setup.sh ─────────────────────────────────────────
echo ""
log "Running setup.sh..."
bash setup.sh
