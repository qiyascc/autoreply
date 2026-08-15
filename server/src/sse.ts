import type { FastifyReply } from 'fastify'
import { sessionEvents, type SessionEvent } from './events'

/**
 * Attaches an SSE stream for a session to the raw response. Both the phone app and
 * the browser link page use this, so a status change lands on both surfaces at once.
 */
export function streamSession(reply: FastifyReply, sessionId: string): void {
  const res = reply.raw
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    // Belt and braces: nginx is also configured with proxy_buffering off for this path.
    'X-Accel-Buffering': 'no',
  })

  const write = (event: SessionEvent) => {
    res.write(`event: ${event.type}\n`)
    res.write(`data: ${JSON.stringify(event)}\n\n`)
  }

  // Bring a late subscriber up to date before streaming live events.
  for (const event of sessionEvents.replay(sessionId)) write(event)

  const unsubscribe = sessionEvents.subscribe(sessionId, write)
  const heartbeat = setInterval(() => res.write(': ping\n\n'), 25_000)

  const cleanup = () => {
    clearInterval(heartbeat)
    unsubscribe()
  }
  reply.raw.on('close', cleanup)
  reply.raw.on('error', cleanup)
}
