import { Boom } from '@hapi/boom'
import pino from 'pino'
import QRCode from 'qrcode'
import makeWASocket, {
  Browsers,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  type WASocket,
} from 'baileys'
import { config } from './config'
import { db, now, queries, type SessionRow, type SessionStatus } from './db'
import { sessionEvents } from './events'
import { useSqliteAuthState } from './auth-state'

const log = pino({ level: config.logLevel }).child({ module: 'wa' })
/** Baileys is extremely chatty at info level; keep its own logger quiet. */
const baileysLogger = pino({ level: 'error' }) as any

/** WhatsApp rotates the QR roughly every 20 s before the pairing window lapses. */
const QR_TTL_MS = 20_000

export class SendError extends Error {
  constructor(
    message: string,
    readonly code:
      | 'not_connected'
      | 'not_on_whatsapp'
      | 'timeout'
      | 'unknown_session'
      | 'needs_pairing'
      | 'send_failed',
  ) {
    super(message)
  }
}

type Runtime = {
  id: string
  deviceId: string
  phone: string
  sock: WASocket | null
  clear: () => void
  /** Set once the browser/app explicitly asked for a pairing code instead of a QR. */
  wantsPairingCode: boolean
  pairingCodeIssued: boolean
  /** The live 8-character code for the current socket, or null if none was issued. */
  pairingCode: string | null
  reconnectAttempts: number
  reconnectTimer: NodeJS.Timeout | null
  /** True while we are intentionally tearing the socket down, so `close` is not retried. */
  stopping: boolean
}

class SessionManager {
  private runtimes = new Map<string, Runtime>()

  /** Re-open every session that was live before the process restarted. */
  async resumeAll(): Promise<void> {
    const rows = queries.allResumableSessions.all()
    log.info({ count: rows.length }, 'resuming sessions')
    for (const row of rows) {
      try {
        await this.start(row)
      } catch (err) {
        log.error({ err, sessionId: row.id }, 'failed to resume session')
      }
    }
  }

  isConnected(sessionId: string): boolean {
    const rt = this.runtimes.get(sessionId)
    return Boolean(rt?.sock?.user)
  }

  async start(session: SessionRow): Promise<void> {
    const existing = this.runtimes.get(session.id)
    if (existing && existing.sock) return

    const { state, saveCreds, clear } = await useSqliteAuthState(session.id)
    const { version } = await fetchLatestBaileysVersion()

    const rt: Runtime = existing ?? {
      id: session.id,
      deviceId: session.device_id,
      phone: session.phone,
      sock: null,
      clear,
      wantsPairingCode: false,
      pairingCodeIssued: false,
      pairingCode: null,
      reconnectAttempts: 0,
      reconnectTimer: null,
      stopping: false,
    }
    rt.clear = clear
    rt.stopping = false
    // A new socket means a new registration attempt: any code from the old one is dead.
    rt.pairingCodeIssued = false
    rt.pairingCode = null
    this.runtimes.set(session.id, rt)

    // Persist the freshly generated identity keys immediately, so a restart midway
    // through pairing resumes the same registration instead of silently starting over.
    await saveCreds()

    const sock = makeWASocket({
      version,
      logger: baileysLogger,
      printQRInTerminal: false,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, baileysLogger),
      },
      // A desktop browser signature is what WhatsApp expects for a linked-device session.
      browser: Browsers.ubuntu('Chrome'),
      markOnlineOnConnect: false,
      syncFullHistory: false,
      generateHighQualityLinkPreview: false,
    })
    rt.sock = sock

    sock.ev.on('creds.update', saveCreds)

    sock.ev.on('connection.update', (update) => {
      void this.onConnectionUpdate(rt, update).catch((err) =>
        log.error({ err, sessionId: rt.id }, 'connection.update handler failed'),
      )
    })
  }

  private async onConnectionUpdate(rt: Runtime, update: any): Promise<void> {
    const { connection, lastDisconnect, qr } = update

    if (qr) {
      this.setStatus(rt.id, 'pairing', null)

      // The pairing code can only be requested once the socket has a live connection,
      // which is exactly when the first QR is offered.
      if (rt.wantsPairingCode && !rt.pairingCodeIssued) {
        await this.issuePairingCode(rt)
      }

      // Once a code is out, WhatsApp expects it to be typed; publishing rotating QRs
      // on top of it would only replace the code the user is halfway through entering.
      if (!rt.pairingCode) {
        const qrDataUrl = await QRCode.toDataURL(qr, { margin: 1, width: 320 })
        sessionEvents.publish(rt.id, { type: 'qr', qrDataUrl, expiresInMs: QR_TTL_MS })
      }
    }

    if (connection === 'open') {
      rt.reconnectAttempts = 0
      rt.pairingCodeIssued = false
      rt.pairingCode = null
      rt.wantsPairingCode = false
      const jid = rt.sock?.user?.id ?? null
      const ts = now()
      queries.markSessionConnected.run(jid, ts, ts, rt.id)
      // A successful link burns the one-time URL; later visits get a genuine 404.
      queries.consumeLinkTokensForSession.run(ts, rt.id)
      sessionEvents.publish(rt.id, { type: 'status', status: 'connected', jid })
      sessionEvents.publish(rt.id, { type: 'connected', jid: jid ?? '', phone: rt.phone })
      log.info({ sessionId: rt.id, jid }, 'session connected')
      return
    }

    if (connection === 'close') {
      const boom = lastDisconnect?.error as Boom | undefined
      const statusCode = boom?.output?.statusCode
      const reason = describeDisconnect(statusCode)
      sessionEvents.publish(rt.id, { type: 'closed', reason })

      if (rt.stopping) return

      // 515 is the mandatory restart right after a pairing code is accepted.
      if (statusCode === DisconnectReason.restartRequired) {
        log.info({ sessionId: rt.id }, 'restart required, reconnecting immediately')
        rt.sock = null
        await this.restart(rt.id, 0)
        return
      }

      // Only an explicit logout destroys credentials. Everything else keeps them: once
      // the auth keys are gone the only way back is re-pairing by hand, so throwing them
      // away on a transient error costs far more than a few pointless reconnects.
      if (statusCode === DisconnectReason.loggedOut) {
        log.warn({ sessionId: rt.id, statusCode, reason }, 'unlinked from the phone')
        rt.clear()
        rt.sock = null
        rt.pairingCodeIssued = false
        this.setStatus(rt.id, 'logged_out', reason)
        return
      }

      // Retrying these only starts a fight with whatever ended the session, but the
      // credentials stay put so an explicit reconnect can still recover.
      if (
        statusCode === DisconnectReason.forbidden ||
        statusCode === DisconnectReason.connectionReplaced
      ) {
        log.warn({ sessionId: rt.id, statusCode, reason }, 'session stopped, not retrying')
        rt.sock = null
        this.setStatus(rt.id, 'disconnected', reason)
        return
      }

      rt.sock = null
      this.setStatus(rt.id, 'disconnected', reason)
      const delay = Math.min(
        config.reconnectMaxMs,
        config.reconnectMinMs * 2 ** rt.reconnectAttempts,
      )
      rt.reconnectAttempts += 1
      log.info({ sessionId: rt.id, delay, attempt: rt.reconnectAttempts }, 'scheduling reconnect')
      await this.restart(rt.id, delay)
    }
  }

  private async restart(sessionId: string, delayMs: number): Promise<void> {
    const rt = this.runtimes.get(sessionId)
    if (!rt) return
    if (rt.reconnectTimer) clearTimeout(rt.reconnectTimer)
    rt.reconnectTimer = setTimeout(() => {
      rt.reconnectTimer = null
      const row = queries.sessionById.get(sessionId)
      if (!row || row.status === 'logged_out') return
      this.start(row).catch((err) =>
        log.error({ err, sessionId }, 'reconnect attempt failed'),
      )
    }, delayMs)
  }

  private setStatus(sessionId: string, status: SessionStatus, error: string | null): void {
    queries.updateSessionStatus.run(status, now(), error, sessionId)
    sessionEvents.publish(sessionId, { type: 'status', status, error })
  }

  private async issuePairingCode(rt: Runtime): Promise<void> {
    if (!rt.sock) throw new SendError('socket not ready', 'not_connected')
    if (rt.sock.authState.creds.registered) return
    rt.pairingCodeIssued = true
    try {
      const code = await rt.sock.requestPairingCode(rt.phone)
      rt.pairingCode = code
      log.info({ sessionId: rt.id }, 'pairing code issued')
      sessionEvents.publish(rt.id, { type: 'pairing-code', code })
    } catch (err) {
      rt.pairingCodeIssued = false
      log.error({ err, sessionId: rt.id }, 'requestPairingCode failed')
      throw err
    }
  }

  /**
   * Ask WhatsApp for an 8-digit pairing code. If the socket has not produced its first
   * QR yet the request is queued and fulfilled as soon as the connection is live.
   */
  async requestPairingCode(sessionId: string): Promise<string | null> {
    const rt = this.runtimes.get(sessionId)
    if (!rt) throw new SendError('unknown session', 'unknown_session')
    rt.wantsPairingCode = true

    if (rt.pairingCode) return rt.pairingCode

    if (rt.sock && !rt.pairingCodeIssued) {
      await this.issuePairingCode(rt)
      return rt.pairingCode
    }
    // Not ready yet — the connection.update handler will issue it and push over SSE.
    return null
  }

  async send(
    sessionId: string,
    toNumber: string,
    text: string,
  ): Promise<{ messageId: string | null }> {
    const rt = this.runtimes.get(sessionId)
    const row = queries.sessionById.get(sessionId)
    if (!rt || !row) throw new SendError('unknown session', 'unknown_session')
    if (!rt.sock?.user) throw new SendError('bridge is not connected to WhatsApp', 'not_connected')

    const digits = toNumber.replace(/\D/g, '')
    if (digits.length < 8) throw new SendError('invalid destination number', 'send_failed')

    const results = await rt.sock.onWhatsApp(`${digits}@s.whatsapp.net`)
    const match = results?.find((r) => r.exists)
    if (!match) {
      this.recordSend(row, digits, text, null, 'failed', 'number is not on WhatsApp')
      throw new SendError('destination number is not on WhatsApp', 'not_on_whatsapp')
    }

    try {
      const sent = await withTimeout(
        rt.sock.sendMessage(match.jid, { text }),
        config.sendTimeoutMs,
      )
      const messageId = sent?.key?.id ?? null
      queries.bumpMessagesSent.run(now(), sessionId)
      this.recordSend(row, digits, text, messageId, 'sent', null)
      return { messageId }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      this.recordSend(row, digits, text, null, 'failed', message)
      if (message === 'timeout') throw new SendError('WhatsApp send timed out', 'timeout')
      throw new SendError(message, 'send_failed')
    }
  }

  private recordSend(
    row: SessionRow,
    to: string,
    body: string,
    messageId: string | null,
    status: 'sent' | 'failed',
    error: string | null,
  ): void {
    queries.insertSentMessage.run(
      row.id,
      row.device_id,
      to,
      body,
      messageId,
      status,
      error,
      now(),
    )
  }

  /** True while the session still holds usable credentials, i.e. can reconnect without re-pairing. */
  hasCredentials(sessionId: string): boolean {
    const row = queries.countCreds.get(sessionId)
    return (row?.n ?? 0) > 0
  }

  /**
   * Brings a stopped session back without re-pairing. Only useful while the credentials
   * survive — after an explicit logout there is nothing left to reconnect with.
   */
  async reconnect(sessionId: string): Promise<void> {
    const row = queries.sessionById.get(sessionId)
    if (!row) throw new SendError('unknown session', 'unknown_session')
    if (this.isConnected(sessionId)) return
    if (!this.hasCredentials(sessionId)) {
      throw new SendError('this session has no credentials left — pair again', 'needs_pairing')
    }

    const rt = this.runtimes.get(sessionId)
    if (rt) {
      if (rt.reconnectTimer) clearTimeout(rt.reconnectTimer)
      rt.reconnectTimer = null
      rt.reconnectAttempts = 0
      rt.stopping = false
      rt.sock = null
    }
    queries.updateSessionStatus.run('disconnected', now(), null, sessionId)
    await this.start({ ...row, status: 'disconnected' })
  }

  async logout(sessionId: string): Promise<void> {
    const rt = this.runtimes.get(sessionId)
    if (rt) {
      rt.stopping = true
      if (rt.reconnectTimer) clearTimeout(rt.reconnectTimer)
      try {
        await rt.sock?.logout()
      } catch {
        /* the socket may already be dead; the local teardown below is what matters */
      }
      rt.clear()
      rt.sock = null
      this.runtimes.delete(sessionId)
    }
    queries.authKeysClear.run(sessionId)
    this.setStatus(sessionId, 'logged_out', 'logged out by user')
    sessionEvents.forget(sessionId)
  }

  async destroy(sessionId: string): Promise<void> {
    await this.logout(sessionId).catch(() => undefined)
    db.transaction(() => {
      queries.authKeysClear.run(sessionId)
      queries.deleteSession.run(sessionId)
    })()
  }
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms)
    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (err) => {
        clearTimeout(timer)
        reject(err)
      },
    )
  })
}

function describeDisconnect(statusCode: number | undefined): string {
  if (statusCode === undefined) return 'connection lost'
  const name = (DisconnectReason as Record<number, string>)[statusCode]
  return name ? `${name} (${statusCode})` : `disconnected (${statusCode})`
}

export const sessions = new SessionManager()
