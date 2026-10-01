import { effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';
@Injectable({ providedIn: 'root' })
export class BinbazarPriceCapRepository {
  private readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  readonly state = signal<{ kind: 'loading' | 'loaded' | 'error'; value: number | null }>({
    kind: 'loading',
    value: null,
  });
  readonly editing = signal(false);
  readonly saving = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  private context = this.auth.admin();
  private ticket = 0;
  constructor() {
    effect(() => {
      const context = this.auth.admin();
      if (context === this.context) return;
      this.context = context;
      this.ticket++;
      this.state.set({ kind: 'loading', value: null });
      this.editing.set(false);
      this.saving.set(false);
      this.error.set('');
      this.notice.set('');
    });
  }
  async load() {
    const admin = this.auth.admin(),
      ticket = ++this.ticket;
    this.state.set({ kind: 'loading', value: null });
    if (!admin) return;
    try {
      const client = await this.gateway.getClient();
      const r = await client.rpc('get_binbazar_price_cap_v1');
      if (
        r.error ||
        !Array.isArray(r.data) ||
        r.data.length !== 1 ||
        !(
          r.data[0].binbazar_max_price === null ||
          (Number.isInteger(r.data[0].binbazar_max_price) && r.data[0].binbazar_max_price > 0)
        )
      )
        throw r.error;
      if (this.auth.admin() === admin && ticket === this.ticket)
        this.state.set({ kind: 'loaded', value: r.data[0].binbazar_max_price });
    } catch {
      if (this.auth.admin() === admin && ticket === this.ticket)
        this.state.set({ kind: 'error', value: null });
    }
  }
  open() {
    if (this.auth.admin()?.role !== 'ADMIN_A' || this.saving() || this.state().kind !== 'loaded')
      return;
    this.error.set('');
    this.notice.set('');
    this.editing.set(true);
  }
  close() {
    if (!this.saving()) this.editing.set(false);
  }
  async save(value: number) {
    const admin = this.auth.admin();
    if (!admin || admin.role !== 'ADMIN_A' || this.saving()) return;
    this.saving.set(true);
    this.error.set('');
    this.notice.set('');
    try {
      const client = await this.gateway.getClient();
      const r = await client.rpc('update_binbazar_price_cap_v1', { p_max_price: value });
      if (r.error) throw r.error;
      if (this.auth.admin() !== admin) return;
      this.editing.set(false);
      this.notice.set('Teto global atualizado.');
      await this.load();
    } catch {
      if (this.auth.admin() === admin)
        this.error.set(
          'Não foi possível salvar o teto. Confira o valor e a conexão e tente novamente.',
        );
    } finally {
      if (this.auth.admin() === admin) this.saving.set(false);
    }
  }
}
