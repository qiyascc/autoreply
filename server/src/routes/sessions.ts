import type { FastifyInstance } from 'fastify'
import { config } from '../config'
import { hashToken, newId, now, queries, randomToken, type SessionRow } from '../db'
import { deviceOf, requireDevice } from './auth'
import { SendError, sessions } from '../wa'
import { streamSession } from '../sse'

function normalisePhone(input: string): string | null {
  const digits = (input ?? '').replace(/\D/g, '')
  if (digits.length < 8 || digits.length > 15) return null
  return digits
}

function ownedSession(deviceId: string, sessionId: string): SessionRow | null {
  const row = queries.sessionById.get(sessionId)
  if (!row || row.device_id !== deviceId) return null
  return row
}

export async function sessionRoutes(app: FastifyInstance): Promise<void> {
  /**
   * Create a WhatsApp session and hand back a single-use link. The link is the only
   * place the QR is ever rendered; the code below never logs or stores it in the clear.
   */
  app.post<{ Body: { phone?: string } }>(
    '/v1/sessions',
    { preHandler: requireDevice },
    async (req, reply) => {
      const device = deviceOf(req)
      const phone = normalisePhone(req.body?.phone ?? '')
      if (!phone) return reply.code(400).send({ error: 'invalid_phone' })

      // One live session per device: re-linking replaces whatever came before.
      const previous = queries.activeSessionForDevice.get(device.id)
      if (previous) await sessions.destroy(previous.id).catch(() => undefined)

      const sessionId = newId('ses')
      queries.insertSession.run(sessionId, device.id, phone, 'pending', now())

      const raw = randomToken()
      const expiresAt = now() + config.linkTtlMs
      queries.insertLinkToken.run(hashToken(raw), sessionId, now(), expiresAt)

      const row = queries.sessionById.get(sessionId)!
      await sessions.start(row)

      return reply.send({
        sessionId,
        phone,
        linkUrl: `${config.publicUrl}/link/${raw}`,
        expiresAt,
        expiresInSeconds: Math.floor(config.linkTtlMs / 1000),
      })
    },
  )

  app.get<{ Params: { id: string } }>(
    '/v1/sessions/:id',
    { preHandler: requireDevice },
    async (req, reply) => {
      const row = ownedSession(deviceOf(req).id, req.params.id)
      if (!row) return reply.code(404).send({ error: 'not_found' })
      return {
        id: row.id,
        phone: row.phone,
        status: sessions.isConnected(row.id) ? 'connected' : row.status,
        jid: row.jid,
        connectedAt: row.connected_at,
        messagesSent: row.messages_sent,
        lastError: row.last_error,
      }
    },
  )

  /** Ask for the 8-digit code. Returns null when the socket is still warming up — the
   *  code then arrives over the SSE stream a moment later. */
  app.post<{ Params: { id: string } }>(
    '/v1/sessions/:id/pairing-code',
    { preHandler: requireDevice },
    async (req, reply) => {
      const row = ownedSession(deviceOf(req).id, req.params.id)
      if (!row) return reply.code(404).send({ error: 'not_found' })
      try {
        const code = await sessions.requestPairingCode(row.id)
        return reply.send({ code, pending: code === null })
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        return reply.code(503).send({ error: 'pairing_code_failed', message })
      }
    },
  )

  app.get<{ Params: { id: string } }>(
    '/v1/sessions/:id/stream',
    { preHandler: requireDevice },
    async (req, reply) => {
      const row = ownedSession(deviceOf(req).id, req.params.id)
      if (!row) return reply.code(404).send({ error: 'not_found' })
      streamSession(reply, row.id)
    },
  )

  /**
   * Revives a session that dropped without being unlinked. As long as the credentials
   * survived, this beats making the user pair again.
   */
  app.post('/v1/reconnect', { preHandler: requireDevice }, async (req, reply) => {
    const session = queries.activeSessionForDevice.get(deviceOf(req).id)
      ?? queries.sessionsByDevice.all(deviceOf(req).id)[0]
    if (!session) return reply.code(404).send({ error: 'not_found' })

    try {
      await sessions.reconnect(session.id)
      return reply.send({ ok: true, sessionId: session.id })
    } catch (err) {
      if (err instanceof SendError) {
        return reply.code(409).send({ ok: false, error: err.code, message: err.message })
      }
      throw err
    }
  })

  app.post<{ Params: { id: string } }>(
    '/v1/sessions/:id/logout',
    { preHandler: requireDevice },
    async (req, reply) => {
      const row = ownedSession(deviceOf(req).id, req.params.id)
      if (!row) return reply.code(404).send({ error: 'not_found' })
      await sessions.logout(row.id)
      return reply.send({ ok: true })
    },
  )

  /**
   * The only endpoint the app calls in anger. It answers synchronously so the phone
   * can decide, there and then, whether to raise a "couldn't reply" notification.
   */
  app.post<{ Body: { to?: string; text?: string } }>(
    '/v1/send',
    { preHandler: requireDevice },
    async (req, reply) => {
      const device = deviceOf(req)
      const to = normalisePhone(req.body?.to ?? '')
      const text = (req.body?.text ?? '').trim()
      if (!to) return reply.code(400).send({ error: 'invalid_to' })
      if (!text) return reply.code(400).send({ error: 'empty_text' })

      const session = queries.activeSessionForDevice.get(device.id)
      if (!session) return reply.code(409).send({ error: 'not_linked' })

      try {
        const { messageId } = await sessions.send(session.id, to, text)
        return reply.send({ ok: true, messageId })
      } catch (err) {
        if (err instanceof SendError) {
          const status = err.code === 'not_connected' ? 503 : 502
          return reply.code(status).send({ ok: false, error: err.code, message: err.message })
        }
        throw err
      }
    },
  )
}
