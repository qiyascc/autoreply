import fs from 'node:fs'
import path from 'node:path'
import type { FastifyInstance, FastifyReply } from 'fastify'
import { config } from '../config'
import { hashToken, now, queries, type SessionRow } from '../db'
import { sessions } from '../wa'
import { streamSession } from '../sse'

const pagePath = path.join(config.webDir, 'link.html')

/**
 * Resolves a one-time link token. Expired, consumed and unknown tokens are all
 * indistinguishable from the outside — every failure is a plain 404 so the page
 * never reveals whether a token ever existed.
 */
function resolveToken(token: string): SessionRow | null {
  const row = queries.linkTokenByHash.get(hashToken(token))
  if (!row) return null
  if (row.consumed_at !== null) return null
  if (row.expires_at < now()) return null
  return queries.sessionById.get(row.session_id) ?? null
}

function notFound(reply: FastifyReply): FastifyReply {
  return reply.code(404).type('text/html; charset=utf-8').send(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
     <title>Link expired</title>
     <style>
       :root{color-scheme:light dark}
       body{margin:0;min-height:100vh;display:grid;place-items:center;
            font:400 17px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
            background:#f2f2f7;color:#1c1c1e}
       @media (prefers-color-scheme:dark){body{background:#000;color:#f2f2f7}}
       div{text-align:center;padding:32px;max-width:22rem}
       h1{font-size:22px;font-weight:600;margin:0 0 8px}
       p{margin:0;opacity:.6;font-size:15px}
     </style>
     <div><h1>This link is no longer valid</h1>
     <p>Pairing links can be opened once and expire after ${Math.round(
       config.linkTtlMs / 60000,
     )} minutes. Generate a new one from the app.</p></div>`,
  )
}

export async function linkRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Params: { token: string } }>('/link/:token', async (req, reply) => {
    const session = resolveToken(req.params.token)
    if (!session) return notFound(reply)

    const html = fs
      .readFileSync(pagePath, 'utf8')
      .replaceAll('__TOKEN__', encodeURIComponent(req.params.token))
      .replaceAll('__PHONE__', escapeHtml(formatPhone(session.phone)))

    return reply
      .type('text/html; charset=utf-8')
      .header('Cache-Control', 'no-store')
      .header(
        'Content-Security-Policy',
        "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'",
      )
      .header('Referrer-Policy', 'no-referrer')
      .send(html)
  })

  app.get<{ Params: { token: string } }>('/link/:token/state', async (req, reply) => {
    const session = resolveToken(req.params.token)
    if (!session) return reply.code(404).send({ error: 'not_found' })
    return reply.header('Cache-Control', 'no-store').send({
      phone: session.phone,
      status: sessions.isConnected(session.id) ? 'connected' : session.status,
    })
  })

  app.get<{ Params: { token: string } }>('/link/:token/stream', async (req, reply) => {
    const session = resolveToken(req.params.token)
    if (!session) return reply.code(404).send({ error: 'not_found' })
    streamSession(reply, session.id)
  })

  app.post<{ Params: { token: string } }>('/link/:token/pairing-code', async (req, reply) => {
    const session = resolveToken(req.params.token)
    if (!session) return reply.code(404).send({ error: 'not_found' })
    try {
      const code = await sessions.requestPairingCode(session.id)
      return reply.send({ code, pending: code === null })
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      return reply.code(503).send({ error: 'pairing_code_failed', message })
    }
  })
}

function formatPhone(digits: string): string {
  return `+${digits}`
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!,
  )
}
