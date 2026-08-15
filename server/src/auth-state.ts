import { proto } from 'baileys'
import { BufferJSON, initAuthCreds } from 'baileys'
import type { AuthenticationCreds, AuthenticationState, SignalDataTypeMap } from 'baileys'
import { db, queries } from './db'

/**
 * Baileys ships `useMultiFileAuthState`, which scatters hundreds of small JSON files
 * per session across the filesystem. We keep the same contract but back it with the
 * SQLite database so sessions are transactional and trivially deletable.
 */
export async function useSqliteAuthState(sessionId: string): Promise<{
  state: AuthenticationState
  saveCreds: () => Promise<void>
  clear: () => void
}> {
  const readRaw = (category: string, id: string): any => {
    const row = queries.authKeysGet.get(sessionId, category, id)
    if (!row) return null
    return JSON.parse(row.value, BufferJSON.reviver)
  }

  const writeRaw = (category: string, id: string, value: any): void => {
    if (value === null || value === undefined) {
      queries.authKeysDelete.run(sessionId, category, id)
      return
    }
    queries.authKeysSet.run(sessionId, category, id, JSON.stringify(value, BufferJSON.replacer))
  }

  const creds: AuthenticationCreds = readRaw('creds', 'default') ?? initAuthCreds()

  const state: AuthenticationState = {
    creds,
    keys: {
      get: async <T extends keyof SignalDataTypeMap>(type: T, ids: string[]) => {
        const result: { [id: string]: SignalDataTypeMap[T] } = {}
        for (const id of ids) {
          let value = readRaw(type as string, id)
          // App-state sync keys are protobuf messages and must be rehydrated as such.
          if (type === 'app-state-sync-key' && value) {
            value = proto.Message.AppStateSyncKeyData.fromObject(value)
          }
          if (value) result[id] = value
        }
        return result
      },
      set: async (data) => {
        const tx = db.transaction(() => {
          for (const category of Object.keys(data)) {
            const entries = (data as any)[category] as Record<string, any>
            for (const id of Object.keys(entries)) {
              writeRaw(category, id, entries[id])
            }
          }
        })
        tx()
      },
    },
  }

  return {
    state,
    saveCreds: async () => {
      writeRaw('creds', 'default', creds)
    },
    clear: () => {
      queries.authKeysClear.run(sessionId)
    },
  }
}
