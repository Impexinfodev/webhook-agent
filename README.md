# Webhook Agent

Deploy karo kisi bhi VPS pe — 3 steps mein.

## Steps

### 1. Clone karo VPS pe
```bash
git clone https://github.com/youruser/webhook-agent.git /opt/webhook-agent
cd /opt/webhook-agent
```

### 2. .env banao
```bash
cp .env.example .env
nano .env
```

Fill karo:
```env
PORT=3000                          # koi bhi free port
VPS_TOKEN=<CRM UI se copy karo>
BACKEND_API_URL=https://api.webhook.aashita.ai
ENCRYPTION_KEY=<backend .env wali same key>
```

### 3. Setup script chalao
```bash
bash setup.sh
```

**Script khud karta hai:**
- Node.js install (agar nahi hai)
- npm install
- PM2 install + start
- Port conflict detect karta hai — automatically free port assign karta hai
- Nginx virtual host banata hai
- Firewall port open karta hai
- Public IP detect karke webhook URL print karta hai

### Output
```
Webhook URL:  http://69.62.80.185/deploy
Health check: http://69.62.80.185/health
```

Yahi URL GitHub repo → Settings → Webhooks mein daalo.
