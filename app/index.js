/**
 * WeChatFerry Node.js bridge
 *
 * Initializes the WCF SDK (which injects spy.dll into WeChat),
 * exposes a simple HTTP API bound to WCF_HOST:WCF_PORT (localhost only by default).
 *
 * Security: WCF_HOST defaults to 127.0.0.1 — never set to 0.0.0.0 without
 * a firewall or reverse proxy in front.
 */

'use strict';

const { Wcf } = require('@wechatferry/core');
const express  = require('express');

const WCF_HOST = process.env.WCF_HOST || '127.0.0.1';
const WCF_PORT = parseInt(process.env.WCF_PORT || '10086', 10);
const SDK_PORT = parseInt(process.env.SDK_PORT || '10087', 10); // internal NNG port

const app = express();
app.use(express.json());

// Health endpoint (no auth required — bound to localhost)
app.get('/health', (_req, res) => res.json({ status: 'ok', ts: Date.now() }));

// ── Initialise WCF ─────────────────────────────────────────────────────────
let wcf;

async function initWcf() {
  try {
    console.log(`[WCF] Initialising WeChatFerry SDK on port ${SDK_PORT}...`);
    wcf = new Wcf({ port: SDK_PORT });
    await wcf.start();
    console.log('[WCF] SDK initialised. WeChat injected.');

    // ── Example routes — extend as needed ─────────────────────────────────

    app.get('/contacts', async (_req, res) => {
      try {
        const contacts = await wcf.getContacts();
        res.json(contacts);
      } catch (e) {
        res.status(500).json({ error: e.message });
      }
    });

    app.get('/msgs', async (_req, res) => {
      try {
        const msgs = await wcf.getMsgs();
        res.json(msgs);
      } catch (e) {
        res.status(500).json({ error: e.message });
      }
    });

    app.post('/send', async (req, res) => {
      const { to, text } = req.body || {};
      if (!to || !text) return res.status(400).json({ error: 'Missing to/text' });
      try {
        await wcf.sendTxt(text, to);
        res.json({ ok: true });
      } catch (e) {
        res.status(500).json({ error: e.message });
      }
    });

  } catch (err) {
    console.error('[WCF] Failed to initialise:', err.message);
    process.exit(1);
  }
}

// ── Start HTTP server ─────────────────────────────────────────────────────
app.listen(WCF_PORT, WCF_HOST, async () => {
  console.log(`[HTTP] Listening on http://${WCF_HOST}:${WCF_PORT}`);
  await initWcf();
});

// ── Graceful shutdown ─────────────────────────────────────────────────────
process.on('SIGTERM', async () => {
  console.log('[WCF] SIGTERM received, cleaning up...');
  if (wcf) await wcf.stop().catch(() => {});
  process.exit(0);
});
process.on('SIGINT', async () => {
  if (wcf) await wcf.stop().catch(() => {});
  process.exit(0);
});
