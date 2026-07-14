export type AuthRole = 'TEAM' | 'ADMIN'

export type AuthSession = {
  role: AuthRole
  pin: string
  expiresAt: number
}

export type AuthResponse = {
  role: AuthRole
}
