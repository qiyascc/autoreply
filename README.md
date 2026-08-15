# Autoreply

Answers the calls you miss, so you don't have to.

When a call comes in and you don't pick up, Autoreply waits a minute, checks that you
haven't already dealt with the person, works out how many times they've tried, and sends
the message you configured for that situation — as a text, on WhatsApp, or both.

Built by **Qiyas CC**.

---

## The shape of it

```
┌─ Android app (cc.ubermensch.ctm) ─────────────────────────┐
│  Flutter UI (Cupertino, English, light/dark)              │
│      ↕ MethodChannel                                      │
│  Kotlin engine — owns the database and every background   │
│  path, because they must run with no Flutter engine alive │
│    · PhoneStateReceiver   ring → idle without offhook     │
│    · AlarmScheduler       exact alarm at T+60s            │
│    · Dispatcher           cancellation checks, rules, send│
│    · SmsSender            SmsManager, silent              │
│    · BridgeClient         HTTPS → the bridge              │
│    · WatchdogService      foreground service              │
└───────────────────────────────────────────────────────────┘
                              ↓ HTTPS
┌─ Bridge (this server) ────────────────────────────────────┐
│  https://ctm.ubermensch.cc                                │
│  Node 20 · Fastify · better-sqlite3 · baileys 6.7.24      │
│  systemd: ctm-bridge.service (user: ctm)                  │
└───────────────────────────────────────────────────────────┘
```

**No Firebase, no push service, no third-party Dart packages.** The phone is the brain;
the bridge is a WhatsApp send-pipe that answers synchronously so the app knows straight
away whether to raise a "couldn't reply" notification.

---

## How a missed call becomes a message

1. `PHONE_STATE` reaches `RINGING`. Number and timestamp are stashed in SharedPreferences
   — the process can be killed between broadcasts, so memory is not good enough.
2. It returns to `IDLE` without ever going `OFFHOOK` → a genuine miss. Answered calls,
   rejections and outgoing calls take different paths and are left alone.
3. The call is recorded and an **exact alarm** is set for T+60 s. WorkManager cannot
   honour a one-minute delay under Doze; `setExactAndAllowWhileIdle` can.
4. The alarm wakes `WatchdogService` (a receiver has ~10 s; a dispatch may need more).
5. Before sending anything, every reason *not* to send is checked, cheapest first:
   master switch → quiet hours → block/allow list → **did you already call them back or
   answer a later call?** → have we replied to them in the last N minutes.
6. The attempt count is computed, the first matching rule wins, and its messages go out
   in order, ~3 s apart.

Step 5's call-log re-check is the one that matters most: an "I can't talk right now" text
arriving *after* the conversation already happened is this app's worst failure mode.

---

## Server

### Layout

```
/opt/mobile/server
├── src/            TypeScript sources
├── dist/           compiled output (what systemd runs)
├── web/link.html   the one-time browser pairing page
├── data/bridge.db  SQLite: devices, sessions, auth state, sent log
└── .env            secrets — chmod 600, owned by the ctm user
```

### Operating it

```bash
systemctl status ctm-bridge
journalctl -u ctm-bridge -f

# mint a single-use invite code for a phone (label, days valid)
cd /opt/mobile/server
sudo -u ctm env $(grep -v '^#' .env | xargs -d '\n') node dist/cli/invite.js "Ahmet's phone" 30

# after editing src/
cd /opt/mobile/server && npx tsc -p tsconfig.json && systemctl restart ctm-bridge
```

### API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/devices` | Redeem an invite code → permanent device token |
| `POST` | `/v1/sessions` | Start linking a number → one-time browser link |
| `POST` | `/v1/sessions/:id/pairing-code` | The 8-character WhatsApp code |
| `GET` | `/v1/sessions/:id/stream` | SSE: qr / pairing-code / status |
| `POST` | `/v1/send` | Send a WhatsApp message, answers synchronously |
| `GET` | `/v1/stats` | Connection state and counters |
| `GET` | `/link/:token` | Public pairing page — QR *or* pairing code |

Link tokens are stored as HMACs, live 10 minutes, and are burned the moment a session
connects. Expired, consumed and unknown tokens are all a plain `404`, so the page never
reveals whether a token ever existed.

### TLS renewal caveat

`certbot 5.7.0` on this host cannot run its nginx installer
(`acme.crypto_util.gen_ss_cert` no longer exists), so the 443 block in
`/etc/nginx/sites-available/ctm.ubermensch.cc` is hand-written. Renewal still works —
`certbot renew` rewrites the files in place — but nginx needs a reload afterwards:

```bash
certbot renew --deploy-hook "systemctl reload nginx"
```

---

## App

### Building

The server has everything needed (`/opt/flutter` 3.47.0, `/opt/android-sdk`, JDK 17):

```bash
cd /opt/mobile/app
export PATH=$PATH:/opt/flutter/bin ANDROID_SDK_ROOT=/opt/android-sdk
flutter build apk --release --split-per-abi     # per-ABI, ~19 MB each
flutter build apk --release                     # one fat APK, ~50 MB
```

`android/key.properties` and `android/autoreply-release.jks` hold the release signing
key (CN=Autoreply, O=Qiyas CC, valid 30 years). **Keep them.** Losing the keystore means
future builds cannot upgrade an installed copy — they have to be uninstalled first.

`.github/workflows/build-apk.yml` reproduces the build on GitHub Actions if you ever
want it off this machine. It signs with the debug key unless you add the keystore as a
repository secret.

### Regenerating the icon

```bash
cd /opt/mobile/app && python3 tool/make_icons.py
```

Draws every density, the adaptive-icon layers and the white-on-transparent notification
icon from one script — edit the colours at the top of the file.

---

## Configuration in the app

**Rules** are checked top to bottom; the first match wins. Each one carries a condition
(which call number, optionally an hour window and whether the caller is in your contacts)
and an action (channel plus one or more messages).

Ships with three: first call, second call, third-onwards.

**The call counter** answers "how many times has this person tried?". Its reset mode is
configurable in Settings — the default, *When we talk*, resets the count once you
actually have a conversation, so someone you spoke to this morning starts again at call
#1 tonight. Fixed windows (6 h → 7 d) and *Never* are also available.

**Quiet hours**, a **block/allow list**, a **repeat guard**, and a **dual-SIM picker**
are all in Settings, along with the appearance switch (System / Light / Dark) and the
daily summary time.

---

## WhatsApp: two paths

| | Server bridge *(default)* | On this phone |
|---|---|---|
| How | Baileys session on the server | Opens WhatsApp, taps Send via an accessibility service |
| Phone locked | Works | Does not work |
| On screen | Nothing | WhatsApp flashes up for ~2 s |
| Needs | Bridge + pairing | WhatsApp installed + accessibility permission |
| Ban risk | Real — unofficial client | Minimal — the official app |

The bridge is the default because you asked for nothing to touch the phone. The
on-device path is a switch in Settings, off unless you turn it on.

⚠️ **Baileys is an unofficial WhatsApp client.** Automated outbound messages to people
who have not messaged you first is exactly the pattern WhatsApp bans numbers for. The
risk is real and it is the reason the on-device path exists as an alternative.

Pairing uses the **8-character code**, not a QR — the phone showing the code is the phone
that would have to scan it. `requestPairingCode` is present in every installable Baileys
release (verified back to `@whiskeysockets/baileys@6.4.0`); this project pins `6.7.24`,
the stable `legacy` tag, rather than the 7.0.0 release candidates.

---

## Xiaomi / MIUI

On the Poco M4 Pro 5G, permissions alone are not enough. MIUI keeps its own battery
policy and autostart switch, and with either wrong the OS kills the process between the
ring and the alarm — the app reports itself perfectly healthy while doing nothing.

The setup wizard deep-links to all three and will not let you finish until the Android
ones are granted:

1. **Autostart** — Settings ▸ Apps ▸ Manage apps ▸ Autoreply ▸ Autostart **on**
2. **Battery saver** — same page ▸ Battery saver ▸ **No restrictions**
3. **Lock in Recents** — swipe down on the card in Recents, tap the padlock

Home shows a warning if Android has been refusing to start the background service, which
is what a reset autostart setting looks like from the inside.

---

## Known limits

- **Android only.** iOS cannot detect missed calls in the background, send SMS
  programmatically, or automate WhatsApp. None of this is portable.
- **`SEND_SMS` is Play-restricted.** Fine as a sideloaded APK; a Play listing would need
  the app to be a default SMS handler or an approved exception.
- **Withheld caller IDs are skipped** — there is nothing to reply to.
- **A failed WhatsApp send gives up and notifies**, by choice. There is no silent retry
  queue; a reply arriving hours late is worse than none. Retry by hand from the Detail
  screen.
- **The bridge holds real WhatsApp credentials.** They live in `data/bridge.db` on this
  server. Treat that file as a secret.
