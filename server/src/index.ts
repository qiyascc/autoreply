import Fastify from 'fastify'
import pino from 'pino'
import { config } from './config'
import { purgeExpiredLinkTokens } from './db'
import { deviceRoutes } from './routes/devices'
import { sessionRoutes } from './routes/sessions'
import { linkRoutes } from './routes/link'
import { sessions } from './wa'

const logger = pino({ level: config.logLevel })

async function main(): Promise<void> {
  const app = Fastify({
    logger,
    // nginx terminates TLS in front of us; honour its forwarded headers.
    trustProxy: true,
    bodyLimit: 64 * 1024,
  })

  // Java's HttpURLConnection labels a bodyless POST as form-urlencoded, which Fastify
  // rejects with a 415. Several endpoints legitimately take no body, so treat an empty
  // payload as `{}` rather than making every client send `{}` explicitly.
  app.addContentTypeParser(
    'application/x-www-form-urlencoded',
    { parseAs: 'string' },
    (_req, body, done) => {
      const text = String(body ?? '').trim()
      if (text.length === 0) return done(null, {})
      try {
        done(null, JSON.parse(text))
      } catch {
        done(null, {})
      }
    },
  )

  app.get('/healthz', async () => ({ ok: true, uptime: process.uptime() }))

  await app.register(deviceRoutes)
  await app.register(sessionRoutes)
  await app.register(linkRoutes)

  app.setNotFoundHandler(async (_req, reply) => reply.code(404).send({ error: 'not_found' }))

  await app.listen({ host: config.host, port: config.port })
  logger.info({ host: config.host, port: config.port, publicUrl: config.publicUrl }, 'bridge up')

  // Bring previously linked sessions back online before anything tries to send.
  await sessions.resumeAll()

  purgeExpiredLinkTokens()
  const purgeTimer = setInterval(purgeExpiredLinkTokens, 60 * 60 * 1000)
  purgeTimer.unref()

  const shutdown = (signal: string) => {
    logger.info({ signal }, 'shutting down')
    app.close().finally(() => process.exit(0))
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'))
  process.on('SIGINT', () => shutdown('SIGINT'))
}

main().catch((err) => {
  logger.error({ err }, 'fatal startup error')
  process.exit(1)
})
