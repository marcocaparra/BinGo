import type { AuthSession } from '../types/auth'

const SESSION_KEY = 'bingo-diary-session'

export function getStoredSession(): AuthSession | null {
  const rawSession = sessionStorage.getItem(SESSION_KEY)
  if (!rawSession) {
    return null
  }

  try {
    const parsed = JSON.parse(rawSession) as AuthSession
    if (parsed.expiresAt <= Date.now()) {
      sessionStorage.removeItem(SESSION_KEY)
      return null
    }
    if ((parsed.role === 'TEAM' || parsed.role === 'ADMIN') && parsed.token) {
      return parsed
    }
  } catch {
    sessionStorage.removeItem(SESSION_KEY)
  }

  return null
}

export function storeSession(session: AuthSession) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify(session))
}

export function clearSession() {
  sessionStorage.removeItem(SESSION_KEY)
}
