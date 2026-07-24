# TALEC Order Messages Dashboard

A manual copy/click-to-WhatsApp tool for staff to send order confirmation and dispatch
messages while WhatsApp automation is offline (Meta Cloud API sends are currently paused —
see `apps/whatsapp-api`). Built 2026-07-24.

- **Live dashboard:** https://mfarooqtariq95-svg.github.io/talec-order-dashboard/
- **Admin setup link** (only one that shows the Setup button — see "Setup" below):
  https://mfarooqtariq95-svg.github.io/talec-order-dashboard/?setup=1
- **Backend:** https://talec-whatsapp-webhook.onrender.com (repo:
  [talec-whatsapp-webhook](https://github.com/mfarooqtariq95-svg/talec-whatsapp-webhook),
  local copy at `apps/whatsapp-api` in the main Talec-Claude-project repo)

## What it does

Two tabs, fed by the same order data the backend already collects from Shopify webhooks:

- **Order Confirmation** — every order with a phone number. Message text differs by payment
  type: COD/Bank Transfer get a combined confirm-ask + PKR 200 advance-discount offer + bank
  details (all in one message, since there's no bot listening for a "YES" reply in manual
  mode); PayFast (already paid) gets a plain thank-you/receipt.
- **Dispatch** — only orders that have actually been fulfilled in Shopify (a Shopify
  `orders/fulfilled` webhook sets `dispatchedAt`). Message includes courier, items, amount
  due, and tracking link.

Each row has:
- **Copy** — puts the exact message text on the clipboard (always reliable, no encoding
  involved).
- **Send via WhatsApp** — opens `api.whatsapp.com/send?phone=...` with the message prefilled.
  Staff still have to hit Send themselves in WhatsApp — this is a convenience link, not an
  automated send.
- **Pending / ✓ Sent** — a manual toggle. Staff click it themselves after actually sending;
  nothing marks itself sent automatically.

Auto-refreshes every 20 seconds. Low order volume, so polling is fine — no push/websocket
needed.

## Setup (admin only)

The Setup button/panel is **hidden by default** so staff never see or touch the access key.
It only appears when the URL has `?setup=1`. To configure a new device:

1. Open `https://mfarooqtariq95-svg.github.io/talec-order-dashboard/?setup=1`
2. Enter:
   - **Backend URL:** `https://talec-whatsapp-webhook.onrender.com`
   - **Access Key:** the value of `INTERNAL_API_KEY` from `apps/whatsapp-api/.env` (same key
     used for all the backend's other internal endpoints)
3. Click Save. This is stored in that browser's `localStorage` — one-time per device.

After that, staff can just use the plain URL (no `?setup=1`) and never see the Setup control.

## Backend endpoints this dashboard calls

Added to `apps/whatsapp-api/server.js` (protected by the same `x-api-key: INTERNAL_API_KEY`
header as the server's other internal endpoints):

- `GET /manual/orders?stage=confirmation|dispatch` — returns the message-ready order list for
  a stage.
- `POST /manual/orders/:orderId/status` — body `{ stage, sent }`, flips the manual
  sent/pending flag. Stored separately from the order's real Shopify lifecycle status, so it
  doesn't interfere with the automated pipeline's own state tracking.

These are entirely separate from the automated Graph API send pipeline in the same file —
the dashboard never triggers an actual WhatsApp API call, only reads data and lets staff
send by hand.

## Notable issues hit and fixed while building this (2026-07-24)

**Emoji corruption in WhatsApp deep links.** WhatsApp's click-to-chat text prefill mangles
multi-byte UTF-8 (emoji) into "�" replacement characters on decode — confirmed on both the
`wa.me` and `api.whatsapp.com` domains, so it's not domain-specific. The only reliable fix was
removing emoji from the manual message templates entirely (see `buildManualConfirmationMessage`
/ `buildManualDispatchMessage` in `server.js`). **Copy** was unaffected the whole time, since
clipboard text never goes through URL encoding — only the prefilled-link path broke.

**Order data was being wiped on every Render redeploy.** Render's disk is ephemeral — every
deploy/restart previously reset `data/orders.json` to empty, silently losing order history and
sent/pending status. This actually happened mid-session and cost 13-15 real fulfilled orders
their dispatch data. Fixed by migrating the order store to **Upstash's free Redis REST tier**
(`UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` env vars on Render) — durable across
deploys/restarts at zero cost for this volume. Falls back to the old local file if those env
vars aren't set (e.g. local dev without real Upstash credentials).

**`SHOPIFY_ADMIN_ACCESS_TOKEN` was expired/invalid**, breaking `fetchShopifyOrderOutstanding`
— which meant *every* real fulfillment webhook was silently failing to save dispatch data or
send the dispatch message (not just the ones affected by the disk wipe above). Root cause:
the Shopify app "TALEC WhatsApp Integration" is a Dev Dashboard/OAuth-style app (not an
old-style "legacy custom app" — Shopify blocked creating new legacy custom apps as of
2026-01-01), and its `application_url` in `shopify.app.toml` was still the literal placeholder
`https://example.com` from whenever it was scaffolded. This mismatch blocks the OAuth
authorization-code flow ("redirect_uri and application url must have matching hosts").
Fixed by:
1. Installing the Shopify CLI (`npx @shopify/cli`), linking to the existing app
   (`shopify app config link --client-id <id>`) from a local config project at
   `apps/shopify/whatsapp-integration-config/`.
2. Correcting `application_url` to the real Render URL and adding
   `https://talec-whatsapp-webhook.onrender.com/oauth/shopify/callback` to `redirect_urls`.
3. Deploying (`shopify app deploy --allow-updates`) as a new active version
   (`talec-whatsapp-integration-3`).
4. Adding **temporary** `/oauth/shopify/authorize` + `/oauth/shopify/callback` routes to
   `server.js` to complete the one-time authorization-code exchange and mint a fresh
   `shpat_...` token. **These routes were removed immediately after use** — they were a real
   security exposure (anyone with the URL could have minted themselves a valid token to order
   data) and are not meant to be reintroduced casually. If this ever needs doing again, the
   pattern is documented here rather than in the code.
5. Recovering all 15 orders whose local record had been lost to the disk-wipe issue via a
   (also since-used) `POST /manual/recover-order/:orderId` endpoint that re-derives the full
   order record straight from Shopify's Admin API.

**Local DNS resolver oddity:** the router in use during this session specifically refused to
resolve `app.shopify.com` and `talec-whatsapp-webhook.onrender.com` at times (`REFUSED` /
`ENOTFOUND`) while every other domain worked fine — resolved by adding `8.8.8.8` (Google DNS)
as a secondary DNS server in macOS Network settings. Worth knowing if backend/API calls
mysteriously fail to resolve again on this network.

## Known accepted limitation

None currently outstanding — the Upstash migration above resolved the one open risk
(ephemeral order storage). If Upstash's free-tier limits (10,000 commands/day) are ever
approached, that would need revisiting, but is far beyond this project's order volume today.
