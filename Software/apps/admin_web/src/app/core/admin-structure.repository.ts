import { effect, inject, Injectable, signal } from '@angular/core';
import { AdminRole } from '../admin-access';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';
export interface ManagedSchool {
  school_id: string;
  name: string;
  student_count: number;
  class_count: number;
  admin_count: number;
  machine_count: number;
}
export interface ManagedAdmin {
  admin_id: string;
  name: string;
  email: string;
  role: AdminRole;
  school_id: string | null;
  school_name: string | null;
  status: 'ACTIVE' | 'INACTIVE';
  access_linked: boolean;
}
type State<T> = { kind: 'loading' | 'loaded' | 'error'; rows: T[] };
@Injectable({ providedIn: 'root' })
export class AdminStructureRepository {
  readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  readonly schools = signal<State<ManagedSchool>>({ kind: 'loading', rows: [] });
  readonly admins = signal<State<ManagedAdmin>>({ kind: 'loading', rows: [] });
  readonly operation = signal<{
    kind: 'school-create' | 'admin-create' | 'admin-edit';
    id: string;
  } | null>(null);
  readonly submitting = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  private context = this.auth.admin();
  private tickets = { schools: 0, admins: 0 };
  private draft = { id: '', payload: '' };
  constructor() {
    effect(() => {
      const admin = this.auth.admin();
      if (admin === this.context) return;
      this.context = admin;
      this.tickets.schools++;
      this.tickets.admins++;
      this.schools.set({ kind: 'loading', rows: [] });
      this.admins.set({ kind: 'loading', rows: [] });
      this.operation.set(null);
      this.submitting.set(false);
      this.error.set('');
      this.notice.set('');
      this.draft = { id: '', payload: '' };
    });
  }
  async load(domain: 'schools' | 'admins') {
    const admin = this.auth.admin(),
      ticket = ++this.tickets[domain];
    this[domain].set({ kind: 'loading', rows: [] });
    if (!admin || admin.role === 'ADMIN_C' || (domain === 'schools' && admin.role !== 'ADMIN_A'))
      return;
    try {
      const client = await this.gateway.getClient();
      const r = await client.rpc(
        domain === 'schools' ? 'get_admin_schools_v1' : 'get_managed_admins_v1',
      );
      if (r.error || !Array.isArray(r.data)) throw r.error;
      if (this.auth.admin() === admin && ticket === this.tickets[domain])
        this[domain].set({ kind: 'loaded', rows: r.data });
    } catch {
      if (this.auth.admin() === admin && ticket === this.tickets[domain])
        this[domain].set({ kind: 'error', rows: [] });
    }
  }
  open(kind: 'school-create' | 'admin-create' | 'admin-edit', id = '') {
    if (this.submitting()) return;
    this.error.set('');
    this.notice.set('');
    if (kind !== 'admin-edit') this.draft = { id: crypto.randomUUID(), payload: '' };
    this.operation.set({ kind, id: id || this.draft.id });
  }
  close() {
    if (!this.submitting()) this.operation.set(null);
  }
  async save(payload: Record<string, unknown>) {
    const op = this.operation(),
      admin = this.auth.admin();
    if (!op || !admin || this.submitting()) return;
    if (op.kind !== 'admin-edit') {
      const semantic = JSON.stringify(payload);
      if (this.draft.payload && this.draft.payload !== semantic)
        this.draft.id = crypto.randomUUID();
      this.draft.payload = semantic;
    }
    this.submitting.set(true);
    this.error.set('');
    this.notice.set('');
    try {
      const client = await this.gateway.getClient();
      const r = await client.rpc(
        op.kind === 'school-create'
          ? 'create_admin_school_v1'
          : op.kind === 'admin-create'
            ? 'create_managed_admin_v1'
            : 'update_managed_admin_v1',
        op.kind === 'school-create'
          ? { p_school_id: this.draft.id, ...payload }
          : { p_admin_id: op.kind === 'admin-create' ? this.draft.id : op.id, ...payload },
      );
      if (r.error) throw r.error;
      if (this.auth.admin() !== admin) return;
      this.operation.set(null);
      this.notice.set(
        op.kind === 'school-create'
          ? 'Escola cadastrada.'
          : op.kind === 'admin-create'
            ? 'Identidade administrativa cadastrada. O acesso ainda precisa ser vinculado.'
            : 'Administrador atualizado.',
      );
      await Promise.all([
        this.load('admins'),
        ...(admin.role === 'ADMIN_A' ? [this.load('schools')] : []),
      ]);
    } catch (e) {
      if (this.auth.admin() !== admin) return;
      const message = (e as { message?: string })?.message || '';
      this.error.set(
        message.includes('EMAIL_CONFLICT')
          ? 'Conflito: e-mail já cadastrado.'
          : message.includes('ID_CONFLICT')
            ? 'Conflito: UUID reutilizado com dados diferentes.'
            : message.includes('LAST_ACTIVE_A')
              ? 'É necessário preservar pelo menos um ADMIN_A ativo.'
              : message.includes('SELF_DEACTIVATION')
                ? 'Você não pode inativar sua própria conta.'
                : message.includes('ACCESS_DENIED')
                  ? 'Acesso não autorizado para esta conta ou escola.'
                  : 'Não foi possível salvar. Confira os dados e a conexão e tente novamente.',
      );
    } finally {
      if (this.auth.admin() === admin) this.submitting.set(false);
    }
  }
}
