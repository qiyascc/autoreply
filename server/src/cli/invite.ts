import crypto from 'node:crypto'
import { now, queries } from '../db'

/**
 * Mints a single-use invite code that a phone redeems for a permanent device token.
 *   npm run invite -- "Ahmet's phone" 7
 */
function generateCode(): string {
  // Crockford-ish alphabet: no O/0, I/1, U — codes get read aloud and typed by hand.
  const alphabet = 'ABCDEFGHJKLMNPQRSTVWXYZ23456789'
  const bytes = crypto.randomBytes(12)
  let out = ''
  for (let i = 0; i < 12; i++) {
    out += alphabet[bytes[i]! % alphabet.length]
    if (i % 4 === 3 && i !== 11) out += '-'
  }
  return out
}

const label = process.argv[2] ?? null
const days = Number.parseInt(process.argv[3] ?? '7', 10)
const expiresAt = Number.isFinite(days) && days > 0 ? now() + days * 24 * 60 * 60 * 1000 : null

const code = generateCode()
queries.insertInvite.run(code, label, now(), expiresAt)

process.stdout.write(
  [
    '',
    `  Invite code:  ${code}`,
    `  Label:        ${label ?? '(none)'}`,
    `  Expires:      ${expiresAt ? new Date(expiresAt).toISOString() : 'never'}`,
    '',
    '  Enter this in the app during setup. It can be redeemed once.',
    '',
  ].join('\n'),
)
