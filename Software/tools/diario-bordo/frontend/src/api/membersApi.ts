import type { Member } from '../types/member'
import { request } from './httpClient'

export function getMembers(): Promise<Member[]> {
  return request<Member[]>('/members')
}
