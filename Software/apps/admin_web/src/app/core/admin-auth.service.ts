import { computed, DestroyRef, inject, Injectable, signal } from '@angular/core';
import { Session, SupabaseClient } from '@supabase/supabase-js';
import { AdminContext, parseAdminContext } from './admin-context';
import { AdminSupabaseClient } from './supabase-client';

type SessionState =
  | { kind: 'authenticated'; admin: AdminContext; hasSession: true; message: '' }
  | {
      kind:
        | 'initializing'
        | 'restoring'
        | 'unauthenticated'
        | 'authenticating'
        | 'invalid-credentials'
        | 'unauthorized'
        | 'inactive'
        | 'error'
        | 'signing-out';
      admin: null;
      hasSession: boolean;
      message: string;
    };

@Injectable({ providedIn: 'root' })
export class AdminAuthService {
  private readonly gateway = inject(AdminSupabaseClient);
  private readonly mutableState = signal<SessionState>({
    kind: 'initializing',
    admin: null,
    hasSession: false,
    message: 'Inicializando acesso…',
  });
  readonly state = this.mutableState.asReadonly();
  readonly admin = computed(() => this.state().admin);
  readonly busy = computed(() =>
    ['initializing', 'restoring', 'authenticating', 'signing-out'].includes(this.state().kind),
  );
  private client?: SupabaseClient;
  private subscription?: { unsubscribe(): void };
  private generation = 0;
  private action = false;
  private resolvedToken: string | null = null;
  private destroyed = false;

  constructor() {
    inject(DestroyRef).onDestroy(() => {
      this.destroyed = true;
      this.generation++;
      this.subscription?.unsubscribe();
    });
    void this.restore();
  }

  private set(
    kind: Exclude<SessionState['kind'], 'authenticated'>,
    message = '',
    hasSession = false,
  ) {
    this.mutableState.set({ kind, admin: null, hasSession, message });
  }

  private async connect() {
    const client = (this.client ??= await this.gateway.getClient());
    if (!this.subscription && !this.destroyed) {
      this.subscription = client.auth.onAuthStateChange((event, session) => {
        if (this.destroyed || event === 'INITIAL_SESSION') return;
        if (event === 'SIGNED_OUT') {
          this.generation++;
          this.resolvedToken = null;
          this.set('unauthenticated');
          return;
        }
        if (this.action) return; // login/restore resolve explicitamente, uma unica vez.
        if (['SIGNED_IN', 'TOKEN_REFRESHED', 'USER_UPDATED'].includes(event)) {
          if (session?.access_token === this.resolvedToken && event !== 'USER_UPDATED') return;
          const ticket = ++this.generation;
          this.set('restoring', 'Verificando acesso administrativo…', !!session);
          // Nunca aguarda outra chamada Supabase dentro do lock do listener Auth.
          setTimeout(() => {
            if (!this.destroyed && ticket === this.generation) void this.resolve(session, ticket);
          }, 0);
        }
      }).data.subscription;
    }
    return client;
  }

  async restore() {
    if (this.action || this.destroyed) return;
    this.action = true;
    const ticket = ++this.generation;
    this.set('restoring', 'Restaurando sessão…');
    try {
      const client = await this.connect();
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      await this.resolve(data.session, ticket);
    } catch {
      if (ticket === this.generation)
        this.set(
          'error',
          'Não foi possível restaurar a sessão. Confira a configuração e a conexão e tente novamente.',
          !!this.client,
        );
    } finally {
      this.action = false;
    }
  }

  async login(email: string, password: string) {
    if (this.busy() || this.action) return;
    this.action = true;
    const ticket = ++this.generation;
    this.resolvedToken = null;
    this.set('authenticating', 'Autenticando…');
    try {
      const client = await this.connect();
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) {
        if (ticket === this.generation) {
          const invalid = error.code === 'invalid_credentials';
          this.set(
            invalid ? 'invalid-credentials' : 'error',
            invalid
              ? 'E-mail ou senha inválidos.'
              : 'Não foi possível autenticar. Confira a configuração e a conexão e tente novamente.',
          );
        }
        return;
      }
      await this.resolve(data.session, ticket);
    } catch {
      if (ticket === this.generation)
        this.set(
          'error',
          'Não foi possível autenticar. Confira a configuração e a conexão e tente novamente.',
        );
    } finally {
      this.action = false;
    }
  }

  private async resolve(session: Session | null, ticket: number) {
    if (ticket !== this.generation || this.destroyed) return;
    if (!session) {
      this.resolvedToken = null;
      this.set('unauthenticated');
      return;
    }
    this.set('restoring', 'Verificando acesso administrativo…', true);
    try {
      const { data, error } = await this.client!.rpc('get_my_admin_context_v1');
      if (error) throw error;
      const admin = parseAdminContext(data);
      if (ticket !== this.generation || this.destroyed) return;
      this.resolvedToken = session.access_token;
      if (!admin)
        this.set('unauthorized', 'Esta conta não possui acesso administrativo autorizado.', true);
      else if (admin.status !== 'ACTIVE')
        this.set(
          'inactive',
          'Sua conta administrativa está inativa. Procure o responsável pelo seu acesso.',
          true,
        );
      // Isto e somente o gate da UI. Futuras RPCs devem validar ACTIVE/role/school no banco.
      else this.mutableState.set({ kind: 'authenticated', admin, hasSession: true, message: '' });
    } catch {
      if (ticket === this.generation && !this.destroyed) {
        this.resolvedToken = null;
        this.set(
          'error',
          'Não foi possível verificar o acesso administrativo. Confira a conexão e tente novamente.',
          true,
        );
      }
    }
  }

  async logout() {
    if (this.action) return;
    this.action = true;
    ++this.generation; // Invalida qualquer RPC pendente e remove imediatamente o contexto.
    this.resolvedToken = null;
    this.set('signing-out', 'Encerrando sessão…', true);
    try {
      const client = await this.connect();
      const { error } = await client.auth.signOut({ scope: 'local' });
      if (error) throw error;
      this.set('unauthenticated');
    } catch {
      this.set('error', 'Não foi possível encerrar a sessão. Tente sair novamente.', true);
    } finally {
      this.action = false;
    }
  }
}
