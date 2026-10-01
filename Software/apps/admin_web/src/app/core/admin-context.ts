import { AdminRole } from '../admin-access';

export interface AdminContext {
  readonly id: string;
  readonly name: string;
  readonly email: string;
  readonly role: AdminRole;
  readonly school_id: string | null;
  readonly status: 'ACTIVE' | 'INACTIVE';
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Valida somente a resposta da RPC. Nunca deriva role/escola de claims, URL ou cache.
export function parseAdminContext(data: unknown): AdminContext | null {
  if (!Array.isArray(data) || data.length > 1) throw new Error('Contexto administrativo inválido.');
  if (data.length === 0) return null;
  const row = data[0];
  if (
    !row ||
    typeof row !== 'object' ||
    typeof row.id !== 'string' ||
    !uuid.test(row.id) ||
    typeof row.name !== 'string' ||
    !row.name.trim() ||
    typeof row.email !== 'string' ||
    !row.email.trim() ||
    !['ADMIN_A', 'ADMIN_B', 'ADMIN_C'].includes(row.role) ||
    !['ACTIVE', 'INACTIVE'].includes(row.status) ||
    (row.role === 'ADMIN_A'
      ? row.school_id !== null
      : typeof row.school_id !== 'string' || !uuid.test(row.school_id))
  )
    throw new Error('Contexto administrativo inválido.');
  // Nao propaga campos extras (hashes, claims ou detalhes internos) para a sessao.
  return Object.freeze({
    id: row.id,
    name: row.name,
    email: row.email,
    role: row.role,
    school_id: row.school_id,
    status: row.status,
  });
}
