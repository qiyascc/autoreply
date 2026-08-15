import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import Database from 'better-sqlite3'
import { config } from './config'

fs.mkdirSync(config.dataDir, { recursive: true })

export const db = new Database(config.dbPath)
db.pragma('journal_mode = WAL')
db.pragma('foreign_keys = ON')
db.pragma('busy_timeout = 5000')

db.exec(`
CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  token_hash    TEXT NOT NULL UNIQUE,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER
);

CREATE TABLE IF NOT EXISTS invites (
  code        TEXT PRIMARY KEY,
  label       TEXT,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER,
  used_by     TEXT REFERENCES devices(id) ON DELETE SET NULL,
  used_at     INTEGER
);

CREATE TABLE IF NOT EXISTS sessions (
  id             TEXT PRIMARY KEY,
  device_id      TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  phone          TEXT NOT NULL,
  status         TEXT NOT NULL,
  jid            TEXT,
  created_at     INTEGER NOT NULL,
  connected_at   INTEGER,
  last_seen_at   INTEGER,
  messages_sent  INTEGER NOT NULL DEFAULT 0,
  last_error     TEXT
);
CREATE INDEX IF NOT EXISTS idx_sessions_device ON sessions(device_id);

CREATE TABLE IF NOT EXISTS link_tokens (
  token_hash  TEXT PRIMARY KEY,
  session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,
  consumed_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_link_tokens_session ON link_tokens(session_id);

CREATE TABLE IF NOT EXISTS auth_keys (
  session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  category    TEXT NOT NULL,
  key_id      TEXT NOT NULL,
  value       TEXT NOT NULL,
  PRIMARY KEY (session_id, category, key_id)
);

CREATE TABLE IF NOT EXISTS sent_messages (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id     TEXT NOT NULL,
  device_id      TEXT NOT NULL,
  to_number      TEXT NOT NULL,
  body           TEXT,
  wa_message_id  TEXT,
  status         TEXT NOT NULL,
  error          TEXT,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sent_session_time ON sent_messages(session_id, created_at);
`)

/** Opaque tokens are stored only as HMACs so a database leak cannot be replayed. */
export function hashToken(raw: string): string {
  return crypto.createHmac('sha256', config.secret).update(raw).digest('hex')
}

export function randomToken(bytes = 32): string {
  return crypto.randomBytes(bytes).toString('base64url')
}

export function newId(prefix: string): string {
  return `${prefix}_${crypto.randomBytes(12).toString('hex')}`
}

export function now(): number {
  return Date.now()
}

export type DeviceRow = {
  id: string
  name: string
  token_hash: string
  created_at: number
  last_seen_at: number | null
}

export type SessionStatus =
  | 'pending'
  | 'pairing'
  | 'connected'
  | 'disconnected'
  | 'logged_out'

export type SessionRow = {
  id: string
  device_id: string
  phone: string
  status: SessionStatus
  jid: string | null
  created_at: number
  connected_at: number | null
  last_seen_at: number | null
  messages_sent: number
  last_error: string | null
}

export type LinkTokenRow = {
  token_hash: string
  session_id: string
  created_at: number
  expires_at: number
  consumed_at: number | null
}

export const queries = {
  deviceByTokenHash: db.prepare<[string], DeviceRow>(
    'SELECT * FROM devices WHERE token_hash = ?',
  ),
  touchDevice: db.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?'),
  insertDevice: db.prepare(
    'INSERT INTO devices (id, name, token_hash, created_at) VALUES (?, ?, ?, ?)',
  ),

  inviteByCode: db.prepare<[string], { code: string; expires_at: number | null; used_by: string | null }>(
    'SELECT code, expires_at, used_by FROM invites WHERE code = ?',
  ),
  consumeInvite: db.prepare(
    'UPDATE invites SET used_by = ?, used_at = ? WHERE code = ? AND used_by IS NULL',
  ),
  insertInvite: db.prepare(
    'INSERT INTO invites (code, label, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ),

  sessionById: db.prepare<[string], SessionRow>('SELECT * FROM sessions WHERE id = ?'),
  sessionsByDevice: db.prepare<[string], SessionRow>(
    'SELECT * FROM sessions WHERE device_id = ? ORDER BY created_at DESC',
  ),
  activeSessionForDevice: db.prepare<[string], SessionRow>(
    `SELECT * FROM sessions WHERE device_id = ? AND status IN ('pending','pairing','connected','disconnected')
     ORDER BY created_at DESC LIMIT 1`,
  ),
  allResumableSessions: db.prepare<[], SessionRow>(
    `SELECT * FROM sessions WHERE status IN ('connected','disconnected','pairing') ORDER BY created_at`,
  ),
  insertSession: db.prepare(
    'INSERT INTO sessions (id, device_id, phone, status, created_at) VALUES (?, ?, ?, ?, ?)',
  ),
  updateSessionStatus: db.prepare(
    'UPDATE sessions SET status = ?, last_seen_at = ?, last_error = ? WHERE id = ?',
  ),
  markSessionConnected: db.prepare(
    `UPDATE sessions SET status = 'connected', jid = ?, connected_at = COALESCE(connected_at, ?),
     last_seen_at = ?, last_error = NULL WHERE id = ?`,
  ),
  bumpMessagesSent: db.prepare(
    'UPDATE sessions SET messages_sent = messages_sent + 1, last_seen_at = ? WHERE id = ?',
  ),
  deleteSession: db.prepare('DELETE FROM sessions WHERE id = ?'),

  insertLinkToken: db.prepare(
    'INSERT INTO link_tokens (token_hash, session_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  ),
  linkTokenByHash: db.prepare<[string], LinkTokenRow>(
    'SELECT * FROM link_tokens WHERE token_hash = ?',
  ),
  consumeLinkTokensForSession: db.prepare(
    'UPDATE link_tokens SET consumed_at = ? WHERE session_id = ? AND consumed_at IS NULL',
  ),

  authKeysGet: db.prepare<[string, string, string], { value: string }>(
    'SELECT value FROM auth_keys WHERE session_id = ? AND category = ? AND key_id = ?',
  ),
  authKeysSet: db.prepare(
    `INSERT INTO auth_keys (session_id, category, key_id, value) VALUES (?, ?, ?, ?)
     ON CONFLICT(session_id, category, key_id) DO UPDATE SET value = excluded.value`,
  ),
  authKeysDelete: db.prepare(
    'DELETE FROM auth_keys WHERE session_id = ? AND category = ? AND key_id = ?',
  ),
  authKeysClear: db.prepare('DELETE FROM auth_keys WHERE session_id = ?'),
  countCreds: db.prepare<[string], { n: number }>(
    "SELECT COUNT(*) AS n FROM auth_keys WHERE session_id = ? AND category = 'creds'",
  ),

  insertSentMessage: db.prepare(
    `INSERT INTO sent_messages (session_id, device_id, to_number, body, wa_message_id, status, error, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ),
  countSentSince: db.prepare<[string, number], { n: number }>(
    "SELECT COUNT(*) AS n FROM sent_messages WHERE session_id = ? AND status = 'sent' AND created_at >= ?",
  ),
}

export function purgeExpiredLinkTokens(): void {
  db.prepare('DELETE FROM link_tokens WHERE expires_at < ?').run(now() - 24 * 60 * 60 * 1000)
}

export { path }
