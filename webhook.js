/**
 * Webhook Listener — runs on EACH VPS independently
 *
 * Required .env on each VPS:
 *   PORT=3000
 *   VPS_TOKEN=<token from CRM UI — unique per VPS>
 *   BACKEND_API_URL=https://api.webhook.aashita.ai
 *   ENCRYPTION_KEY=<same 64-char hex as backend>
 */
require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const crypto = require('crypto');
const https = require('https');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3000;
const VPS_TOKEN = process.env.VPS_TOKEN;
const BACKEND_API_URL = (process.env.BACKEND_API_URL || 'http://localhost:4000').replace(/\/$/, '');

if (!VPS_TOKEN) {
    console.error('[Webhook] ERROR: VPS_TOKEN not set — add this VPS in the CRM UI and copy the token here');
    process.exit(1);
}

// ── Decrypt webhook secret stored encrypted in DB ─────────────────────────────
function decrypt(encoded) {
    const keyHex = process.env.ENCRYPTION_KEY;
    if (!keyHex) throw new Error('ENCRYPTION_KEY not set');
    const key = Buffer.from(keyHex.slice(0, 64), 'hex');
    const [ivHex, tagHex, dataHex] = encoded.split(':');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    return decipher.update(Buffer.from(dataHex, 'hex')) + decipher.final('utf8');
}

// ── Simple HTTP/HTTPS POST helper (no extra deps) ─────────────────────────────
function apiPost(path, body) {
    return new Promise((resolve, reject) => {
        const url = new URL(BACKEND_API_URL + path);
        const data = JSON.stringify(body);
        const lib = url.protocol === 'https:' ? https : http;
        const req = lib.request({
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname,
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
        }, (res) => {
            let raw = '';
            res.on('data', c => raw += c);
            res.on('end', () => { try { resolve(JSON.parse(raw)); } catch { resolve({}); } });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

// ── In-memory deploy map refreshed every 60s via backend heartbeat ────────────
let deployMap = {};   // "repo:branch" → project doc
let myVpsId = null;
let myVpsName = 'unknown';

async function heartbeat() {
    try {
        const res = await apiPost('/api/vps/heartbeat', { vpsToken: VPS_TOKEN });
        if (res.error) { console.error('[Webhook] Heartbeat rejected:', res.error); return; }
        myVpsId = res.vpsId;
        myVpsName = res.vpsName || 'VPS';
        const map = {};
        (res.projects || []).forEach(p => { map[`${p.repo}:${p.branch}`] = p; });
        deployMap = map;
        console.log(`[Webhook] [${myVpsName}] ${Object.keys(deployMap).length} project(s) loaded`);
    } catch (err) {
        console.error('[Webhook] Heartbeat failed:', err.message);
    }
}

setInterval(heartbeat, 60_000);

// ── Webhook endpoint ──────────────────────────────────────────────────────────
app.use(bodyParser.json());

app.post('/deploy', async (req, res) => {
    const startTime = Date.now();
    try {
        const repo = req.body?.repository?.name?.toLowerCase();
        const ref = req.body?.ref;
        const pusher = req.body?.pusher?.name || req.body?.sender?.login || 'unknown';
        const commitSha = req.body?.after || req.body?.head_commit?.id || '';
        const commitMessage = req.body?.head_commit?.message?.split('\n')[0] || '';

        if (!repo || !ref) return res.status(400).send('Invalid payload');

        const branchName = ref.replace('refs/heads/', '');
        const project = deployMap[`${repo}:${branchName}`];

        if (!project) {
            console.log(`[Webhook] No project for ${repo}/${branchName}`);
            return res.status(200).send('No action taken');
        }

        // Verify GitHub HMAC signature
        const signature = req.headers['x-hub-signature-256'];
        if (!signature) return res.status(401).send('No signature');

        let plainSecret;
        try { plainSecret = decrypt(project.webhookSecret); }
        catch { return res.status(500).send('Secret decryption failed'); }

        const digest = 'sha256=' + crypto.createHmac('sha256', plainSecret)
            .update(JSON.stringify(req.body)).digest('hex');

        try {
            if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest)))
                return res.status(403).send('Invalid signature');
        } catch { return res.status(403).send('Invalid signature'); }

        console.log(`[Webhook] Deploying ${repo}/${branchName} via: ${project.deployScript}`);
        res.status(202).send('Accepted');

        exec(project.deployScript, async (err, stdout, stderr) => {
            const durationMs = Date.now() - startTime;
            const status = err ? 'failed' : 'success';

            // Push log to backend
            apiPost('/api/logs/ingest', {
                vpsToken: VPS_TOKEN, vpsId: myVpsId, projectId: project._id,
                repo, branch: branchName, status,
                triggeredBy: pusher, commitSha, commitMessage,
                stdout: stdout || '', stderr: stderr || '', durationMs
            }).catch(e => console.error('[Webhook] Log ingest failed:', e.message));

            console.log(`[Webhook] ${status.toUpperCase()} ${repo}/${branchName} (${durationMs}ms)`);
        });

    } catch (err) {
        console.error('[Webhook] Error:', err.message);
        res.status(500).send('Server error');
    }
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', vps: myVpsName, projects: Object.keys(deployMap).length });
});

// ── Start ─────────────────────────────────────────────────────────────────────
heartbeat().then(() => {
    app.listen(PORT, () => {
        console.log(`[Webhook] Listening on port ${PORT} | VPS: ${myVpsName}`);
    });
});
