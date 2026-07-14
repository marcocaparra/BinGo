import type { AuthSession } from '../types/auth'

const SESSION_KEY = 'bingo-diary-session'
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000

export function getStoredSession(): AuthSession | null {
  const rawSession = localStorage.getItem(SESSION_KEY)
  if (!rawSession) {
    return null
  }

  try {
    const parsed = JSON.parse(rawSession) as AuthSession
    if (parsed.expiresAt <= Date.now()) {
      localStorage.removeItem(SESSION_KEY)
      return null
    }
    if ((parsed.role === 'TEAM' || parsed.role === 'ADMIN') && parsed.pin) {
      return parsed
    }
  } catch {
    localStorage.removeItem(SESSION_KEY)
  }

  return null
}

export function storeSession(session: AuthSession) {
  localStorage.setItem(SESSION_KEY, JSON.stringify({
    ...session,
    expiresAt: Date.now() + SESSION_TTL_MS,
  }))
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY)
}
