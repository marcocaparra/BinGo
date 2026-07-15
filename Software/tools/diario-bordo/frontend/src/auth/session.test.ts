import { beforeEach, describe, expect, it } from 'vitest'
import { clearSession, getStoredSession, storeSession } from './session'

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>()

  get length() {
    return this.values.size
  }

  clear() {
    this.values.clear()
  }

  getItem(key: string) {
    return this.values.get(key) ?? null
  }

  key(index: number) {
    return Array.from(this.values.keys())[index] ?? null
  }

  removeItem(key: string) {
    this.values.delete(key)
  }

  setItem(key: string, value: string) {
    this.values.set(key, value)
  }
}

describe('session storage', () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, 'sessionStorage', {
      configurable: true,
      value: new MemoryStorage(),
    })
  })

  it('stores only the signed token for the current browser session', () => {
    const session = {
      role: 'TEAM' as const,
      token: 'signed-token',
      expiresAt: Date.now() + 60_000,
    }

    storeSession(session)

    expect(getStoredSession()).toEqual(session)
    expect(sessionStorage.getItem('bingo-diary-session')).not.toContain('pin')
  })

  it('removes expired sessions', () => {
    storeSession({
      role: 'ADMIN',
      token: 'expired-token',
      expiresAt: Date.now() - 1,
    })

    expect(getStoredSession()).toBeNull()
    expect(sessionStorage.length).toBe(0)
  })

  it('clears the current session', () => {
    storeSession({
      role: 'TEAM',
      token: 'signed-token',
      expiresAt: Date.now() + 60_000,
    })

    clearSession()

    expect(getStoredSession()).toBeNull()
  })
})
