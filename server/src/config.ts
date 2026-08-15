import path from 'node:path'

function env(name: string, fallback?: string): string {
  const v = process.env[name]
  if (v === undefined || v === '') {
    if (fallback === undefined) throw new Error(`Missing required env var: ${name}`)
    return fallback
  }
  return v
}

function envInt(name: string, fallback: number): number {
  const v = process.env[name]
  if (!v) return fallback
  const n = Number.parseInt(v, 10)
  if (Number.isNaN(n)) throw new Error(`Env var ${name} must be an integer, got: ${v}`)
  return n
}

const rootDir = path.resolve(__dirname, '..')

export const config = {
  rootDir,
  webDir: path.join(rootDir, 'web'),
  dataDir: env('CTM_DATA_DIR', path.join(rootDir, 'data')),
  dbPath: path.join(env('CTM_DATA_DIR', path.join(rootDir, 'data')), 'bridge.db'),

  host: env('CTM_HOST', '127.0.0.1'),
  port: envInt('CTM_PORT', 9410),

  /** Public origin, used to build the one-time link handed to the app. */
  publicUrl: env('CTM_PUBLIC_URL', 'https://ctm.ubermensch.cc').replace(/\/+$/, ''),

  /** Secret used to derive HMACs for device tokens and link tokens. */
  secret: env('CTM_SECRET'),

  /** How long a one-time pairing link stays valid. */
  linkTtlMs: envInt('CTM_LINK_TTL_SECONDS', 600) * 1000,

  /** Reconnect backoff bounds. */
  reconnectMinMs: envInt('CTM_RECONNECT_MIN_MS', 1_000),
  reconnectMaxMs: envInt('CTM_RECONNECT_MAX_MS', 60_000),

  /** Hard ceiling on how long POST /v1/send may block before giving up. */
  sendTimeoutMs: envInt('CTM_SEND_TIMEOUT_MS', 25_000),

  logLevel: env('CTM_LOG_LEVEL', 'info'),
} as const

export type Config = typeof config
