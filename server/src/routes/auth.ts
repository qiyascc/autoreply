import type { FastifyReply, FastifyRequest } from 'fastify'
import { hashToken, now, queries, type DeviceRow } from '../db'

declare module 'fastify' {
  interface FastifyRequest {
    device?: DeviceRow
  }
}

/** Extracts a device token from `Authorization: Bearer …` or a `?token=` query param. */
export function extractToken(req: FastifyRequest): string | null {
  const header = req.headers.authorization
  if (header?.startsWith('Bearer ')) return header.slice(7).trim()
  const q = (req.query as Record<string, unknown> | undefined)?.token
  return typeof q === 'string' && q.length > 0 ? q : null
}

/**
 * Device authentication. EventSource cannot set headers, so the SSE endpoint is
 * allowed to pass the same token as a query parameter.
 */
export async function requireDevice(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const raw = extractToken(req)
  if (!raw) {
    await reply.code(401).send({ error: 'missing_token' })
    return
  }
  const device = queries.deviceByTokenHash.get(hashToken(raw))
  if (!device) {
    await reply.code(401).send({ error: 'invalid_token' })
    return
  }
  queries.touchDevice.run(now(), device.id)
  req.device = device
}

export function deviceOf(req: FastifyRequest): DeviceRow {
  if (!req.device) throw new Error('requireDevice preHandler did not run')
  return req.device
}
