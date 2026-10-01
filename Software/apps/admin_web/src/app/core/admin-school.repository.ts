import { effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';

export interface SchoolStudent {
  student_id: string;
  name: string;
  email: string | null;
  registration: string | null;
  class_id: string;
  class_name: string;
  status: 'ACTIVE' | 'INACTIVE';
  points_student_balance: number;
  class_points_balance: number;
}
export interface SchoolClass {
  class_id: string;
  segment: string;
  grade: string;
  name: string;
  points_class_balance: number;
  student_count: number;
}
type SchoolState = {
  kind: 'loading' | 'loaded' | 'error';
  students: SchoolStudent[];
  classes: SchoolClass[];
};
export type SchoolOperation = {
  action: 'student-create' | 'student-edit' | 'student-view' | 'class-create' | 'class-edit';
  id: string | null;
};

@Injectable({ providedIn: 'root' })
export class AdminSchoolRepository {
  private readonly gateway = inject(AdminSupabaseClient);
  private readonly auth = inject(AdminAuthService);
  private readonly mutableState = signal<SchoolState>({
    kind: 'loading',
    students: [],
    classes: [],
  });
  readonly state = this.mutableState.asReadonly();
  readonly operation = signal<SchoolOperation | null>(null);
  readonly saving = signal(false);
  readonly mutationError = signal('');
  readonly notice = signal('');
  private generation = 0;
  private readGeneration = 0;
  private context = this.auth.admin();

  constructor() {
    effect(() => {
      // Nenhuma fotografia escolar sobrevive a logout/restauracao/troca de contexto.
      const context = this.auth.admin();
      if (context === this.context) return;
      this.context = context;
      this.generation++;
      this.readGeneration++;
      this.mutableState.set({ kind: 'loading', students: [], classes: [] });
      this.operation.set(null);
      this.saving.set(false);
      this.mutationError.set('');
      this.notice.set('');
    });
  }

  async load() {
    const admin = this.auth.admin();
    const ticket = ++this.readGeneration;
    this.mutableState.set({ kind: 'loading', students: [], classes: [] });
    if (!admin || !['ADMIN_B', 'ADMIN_C'].includes(admin.role)) return;
    try {
      const client = await this.gateway.getClient();
      const [students, classes] = await Promise.all([
        client.rpc('get_admin_students_v1'),
        client.rpc('get_admin_classes_v1'),
      ]);
      if (students.error || classes.error) throw students.error || classes.error;
      if (!Array.isArray(students.data) || !Array.isArray(classes.data))
        throw new Error('Invalid response');
      if (ticket === this.readGeneration && this.auth.admin() === admin)
        this.mutableState.set({ kind: 'loaded', students: students.data, classes: classes.data });
    } catch {
      if (ticket === this.readGeneration && this.auth.admin() === admin)
        this.mutableState.set({ kind: 'error', students: [], classes: [] });
    }
  }

  open(action: SchoolOperation['action'], id: string | null = null) {
    if (this.state().kind !== 'loaded' || this.saving()) return;
    if (action !== 'student-view' && this.auth.admin()?.role !== 'ADMIN_B') return;
    this.mutationError.set('');
    this.notice.set('');
    this.operation.set({ action, id });
  }

  close() {
    if (!this.saving()) this.operation.set(null);
  }

  async submit(form: HTMLFormElement) {
    const op = this.operation();
    if (
      !op ||
      op.action === 'student-view' ||
      this.saving() ||
      this.auth.admin()?.role !== 'ADMIN_B'
    )
      return;
    const ticket = this.generation;
    const admin = this.auth.admin();
    const fields = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
    const student = op.action.startsWith('student-');
    // Contrato fechado: jamais enviar escola, saldo, Auth, PIN ou ator do cliente.
    const parameters: Record<string, string | null> = student
      ? {
          p_name: fields['name'],
          p_email: fields['email'] || null,
          p_registration: fields['registration'],
          p_class_id: fields['class_id'],
          p_status: fields['status'],
        }
      : { p_name: fields['name'], p_segment: fields['segment'], p_grade: fields['grade'] };
    if (op.action.endsWith('-edit')) parameters[student ? 'p_student_id' : 'p_class_id'] = op.id;
    const rpc = `${op.action.endsWith('-create') ? 'create' : 'update'}_admin_${student ? 'student' : 'class'}_v1`;
    this.saving.set(true);
    this.mutationError.set('');
    try {
      const client = await this.gateway.getClient();
      if (ticket !== this.generation || this.auth.admin() !== admin) return;
      const { error } = await client.rpc(rpc, parameters);
      if (error) throw error;
      if (ticket !== this.generation || this.auth.admin() !== admin) return;
      this.operation.set(null);
      this.notice.set('Alterações salvas.');
      await this.load(); // Reconsulta autoritativa; falha de leitura mostra erro, sem mocks.
    } catch (error) {
      if (ticket === this.generation) {
        const code = (error as { code?: string }).code;
        this.mutationError.set(
          code === '23505'
            ? 'Esta matrícula já está em uso nesta escola.'
            : code === '42501'
              ? 'Operação não autorizada para este acesso ou escola.'
              : code === '22023'
                ? 'Confira os campos. Nome e matrícula não podem estar vazios.'
                : 'Não foi possível salvar. Confira a conexão e tente novamente.',
        );
      }
    } finally {
      // Apenas esta sessao pode encerrar seu estado de mutation.
      if (ticket === this.generation) this.saving.set(false);
    }
  }
}
