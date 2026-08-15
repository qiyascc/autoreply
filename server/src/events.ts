import { EventEmitter } from 'node:events'
import type { SessionStatus } from './db'

export type SessionEvent =
  | { type: 'status'; status: SessionStatus; jid?: string | null; error?: string | null }
  | { type: 'qr'; qrDataUrl: string; expiresInMs: number }
  | { type: 'pairing-code'; code: string }
  | { type: 'connected'; jid: string; phone: string }
  | { type: 'closed'; reason: string }

/**
 * A tiny fan-out hub. Both the phone app and the browser link page subscribe to the
 * same session id, so whichever surface the user is looking at sees the same state
 * transition at the same moment.
 */
class SessionEvents {
  private emitter = new EventEmitter()
  /** Last event of each type per session, replayed to late subscribers. */
  private latest = new Map<string, Map<string, SessionEvent>>()

  constructor() {
    this.emitter.setMaxListeners(0)
  }

  publish(sessionId: string, event: SessionEvent): void {
    let bucket = this.latest.get(sessionId)
    if (!bucket) {
      bucket = new Map()
      this.latest.set(sessionId, bucket)
    }
    bucket.set(event.type, event)
    // A successful link makes every prior pairing artefact meaningless.
    if (event.type === 'connected') {
      bucket.delete('qr')
      bucket.delete('pairing-code')
    }
    this.emitter.emit(sessionId, event)
  }

  replay(sessionId: string): SessionEvent[] {
    const bucket = this.latest.get(sessionId)
    return bucket ? [...bucket.values()] : []
  }

  subscribe(sessionId: string, listener: (event: SessionEvent) => void): () => void {
    this.emitter.on(sessionId, listener)
    return () => this.emitter.off(sessionId, listener)
  }

  forget(sessionId: string): void {
    this.latest.delete(sessionId)
    this.emitter.removeAllListeners(sessionId)
  }
}

export const sessionEvents = new SessionEvents()
