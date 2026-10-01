import { effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSchoolRepository } from './admin-school.repository';
import { AdminSupabaseClient } from './supabase-client';

export interface ClassChangeRequest {
  request_id: string;
  student_id: string;
  student_name: string;
  registration: string | null;
  source_class_id: string;
  source_class_name: string;
  destination_class_id: string;
  destination_class_name: string;
  current_class_id: string;
  current_class_name: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'CANCELED';
  is_stale: boolean;
  requested_by_admin_id: string;
  requested_by_admin_name: string;
  created_at: string;
  resolved_by_admin_id: string | null;
  resolved_by_admin_name: string | null;
  resolved_at: string | null;
}
@Injectable({ providedIn: 'root' })
export class ClassChangeRequestsRepository {
  private readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  readonly school = inject(AdminSchoolRepository);
  readonly state = signal<{ kind: 'loading' | 'loaded' | 'error'; rows: ClassChangeRequest[] }>({
    kind: 'loading',
    rows: [],
  });
  readonly operation = signal<{ action: 'create' | 'review' | 'cancel'; id: string | null } | null>(
    null,
  );
  readonly submitting = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  private context = this.auth.admin();
  private readGeneration = 0;
  private draft = { id: '', payload: '' };

  constructor() {
    effect(() => {
      const context = this.auth.admin();
      if (context === this.context) return;
      this.context = context;
      this.readGeneration++;
      this.state.set({ kind: 'loading', rows: [] });
      this.operation.set(null);
      this.submitting.set(false);
      this.error.set('');
      this.notice.set('');
      this.draft = { id: '', payload: '' };
    });
  }
  async load() {
    const admin = this.auth.admin();
    const ticket = ++this.readGeneration;
    this.state.set({ kind: 'loading', rows: [] });
    if (!admin || !['ADMIN_B', 'ADMIN_C'].includes(admin.role)) return;
    try {
      const client = await this.gateway.getClient();
      const [result] = await Promise.all([
        client.rpc('get_class_change_requests_v1'),
        this.school.load(),
      ]);
      if (result.error || !Array.isArray(result.data))
        throw result.error || new Error('Invalid response');
      if (this.auth.admin() === admin && ticket === this.readGeneration)
        this.state.set({ kind: 'loaded', rows: result.data });
    } catch {
      if (this.auth.admin() === admin && ticket === this.readGeneration)
        this.state.set({ kind: 'error', rows: [] });
    }
  }
  open(action: 'create' | 'review' | 'cancel', id: string | null = null) {
    if (this.submitting() || this.state().kind !== 'loaded') return;
    const role = this.auth.admin()?.role;
    if ((action === 'review' && role !== 'ADMIN_B') || (action !== 'review' && role !== 'ADMIN_C'))
      return;
    this.error.set('');
    this.notice.set('');
    if (action === 'create') this.draft = { id: crypto.randomUUID(), payload: '' };
    this.operation.set({ action, id });
  }
  close() {
    if (!this.submitting()) this.operation.set(null);
  }
  selected() {
    return this.state().rows.find((r) => r.request_id === this.operation()?.id);
  }
  async create(form: HTMLFormElement) {
    if (
      this.submitting() ||
      this.auth.admin()?.role !== 'ADMIN_C' ||
      this.operation()?.action !== 'create'
    )
      return;
    const fields = new FormData(form);
    const student = String(fields.get('student_id'));
    const destination = String(fields.get('destination_class_id'));
    const payload = JSON.stringify([student, destination]);
    // Um retry conserva UUID/payload. Editar a intencao cria outro UUID.
    if (this.draft.payload && this.draft.payload !== payload) this.draft.id = crypto.randomUUID();
    this.draft.payload = payload;
    await this.mutate('create_class_change_request_v1', {
      p_request_id: this.draft.id,
      p_student_id: student,
      p_destination_class_id: destination,
    });
  }
  async decide(action: 'approve' | 'reject' | 'cancel') {
    const op = this.operation();
    if (!op?.id) return;
    if (action === 'approve' && this.selected()?.is_stale) return;
    if (
      action === 'cancel'
        ? this.auth.admin()?.role !== 'ADMIN_C'
        : this.auth.admin()?.role !== 'ADMIN_B'
    )
      return;
    await this.mutate(`${action}_class_change_request_v1`, { p_request_id: op.id });
  }
  private async mutate(rpc: string, parameters: Record<string, string>) {
    if (this.submitting()) return;
    const admin = this.auth.admin();
    this.submitting.set(true);
    this.error.set('');
    try {
      const client = await this.gateway.getClient();
      if (this.auth.admin() !== admin) return;
      const result = await client.rpc(rpc, parameters);
      if (result.error) throw result.error;
      if (this.auth.admin() !== admin) return;
      this.operation.set(null);
      this.notice.set(rpc.startsWith('create') ? 'Solicitação enviada.' : 'Decisão registrada.');
      await this.load(); // Inclui fotografia de alunos/turmas apos aprovacao.
    } catch (error) {
      if (this.auth.admin() !== admin) return;
      const failure = error as { code?: string; message?: string };
      const conflict =
        failure.code === '23505' ||
        failure.message?.startsWith('CLASS_CHANGE_DECISION_CONFLICT') ||
        failure.message?.startsWith('CLASS_CHANGE_REQUEST_STALE');
      this.error.set(
        failure.message === 'CLASS_CHANGE_REQUEST_STALE'
          ? 'Conflito: a turma atual mudou. Esta solicitação não pode ser aprovada; atualize ou rejeite.'
          : conflict
            ? 'Conflito: esta solicitação já foi decidida ou o identificador foi reutilizado.'
            : failure.code === '42501'
              ? 'Operação não autorizada para este acesso ou escola.'
              : failure.code === '22023'
                ? 'Selecione um aluno e uma turma diferente da atual.'
                : 'Não foi possível concluir. Confira a conexão e tente novamente.',
      );
      if (conflict) await this.load();
    } finally {
      if (this.auth.admin() === admin) this.submitting.set(false);
    }
  }
}
