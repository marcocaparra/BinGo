import type { AuthResponse, AuthRole } from '../types/auth'
import { request } from './httpClient'

export function accessWithPin(role: AuthRole, pin: string): Promise<AuthResponse> {
  return request<AuthResponse>('/auth/access', {
    method: 'POST',
    body: JSON.stringify({ role, pin }),
  })
}
