export type AuthRole = 'TEAM' | 'ADMIN'

export type AuthSession = {
  role: AuthRole
  token: string
  expiresAt: number
}

export type AuthResponse = {
  role: AuthRole
  token: string
  expiresAt: string
}
