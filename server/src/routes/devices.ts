import type { FastifyInstance } from 'fastify'
import { hashToken, newId, now, queries, randomToken } from '../db'
import { deviceOf, requireDevice } from './auth'
import { sessions } from '../wa'

export async function deviceRoutes(app: FastifyInstance): Promise<void> {
  /**
   * Redeem an invite code for a permanent device token. Invites are single-use, so a
   * leaked code stops working the moment the intended phone has registered.
   */
  app.post<{ Body: { inviteCode?: string; name?: string } }>('/v1/devices', async (req, reply) => {
    const code = (req.body?.inviteCode ?? '').trim().toUpperCase()
    const name = (req.body?.name ?? '').trim() || 'Unnamed device'
    if (!code) return reply.code(400).send({ error: 'invite_code_required' })

    const invite = queries.inviteByCode.get(code)
    if (!invite) return reply.code(403).send({ error: 'invalid_invite' })
    if (invite.used_by) return reply.code(403).send({ error: 'invite_already_used' })
    if (invite.expires_at && invite.expires_at < now()) {
      return reply.code(403).send({ error: 'invite_expired' })
    }

    const deviceId = newId('dev')
    const token = randomToken()
    queries.insertDevice.run(deviceId, name, hashToken(token), now())
    const consumed = queries.consumeInvite.run(deviceId, now(), code)
    if (consumed.changes === 0) {
      // Lost a race against a concurrent redemption of the same code.
      return reply.code(403).send({ error: 'invite_already_used' })
    }

    return reply.send({ deviceId, token, name })
  })

  app.get('/v1/me', { preHandler: requireDevice }, async (req) => {
    const device = deviceOf(req)
    const session = queries.activeSessionForDevice.get(device.id)
    return {
      device: { id: device.id, name: device.name, createdAt: device.created_at },
      session: session
        ? {
            id: session.id,
            phone: session.phone,
            status: sessions.isConnected(session.id) ? 'connected' : session.status,
            jid: session.jid,
            connectedAt: session.connected_at,
            messagesSent: session.messages_sent,
            lastError: session.last_error,
          }
        : null,
    }
  })

  app.get('/v1/stats', { preHandler: requireDevice }, async (req) => {
    const device = deviceOf(req)
    // Fall back to the newest session of any status, so a dropped link reports itself
    // honestly instead of looking like it was never set up.
    const session = queries.activeSessionForDevice.get(device.id)
      ?? queries.sessionsByDevice.all(device.id)[0]
    if (!session) return { linked: false, connected: false, canReconnect: false }

    const dayAgo = now() - 24 * 60 * 60 * 1000
    const today = queries.countSentSince.get(session.id, dayAgo)
    return {
      linked: session.status !== 'logged_out',
      connected: sessions.isConnected(session.id),
      canReconnect:
        !sessions.isConnected(session.id) && sessions.hasCredentials(session.id),
      status: session.status,
      phone: session.phone,
      jid: session.jid,
      connectedAt: session.connected_at,
      lastSeenAt: session.last_seen_at,
      messagesSent: session.messages_sent,
      messagesSentLast24h: today?.n ?? 0,
      lastError: session.last_error,
    }
  })
}
