import { BinbazarPriceCapRepository } from './binbazar-price-cap.repository';
import { effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';
export interface AdminProduct {
  reward_id: string;
  name: string;
  description: string | null;
  category: string | null;
  cost_points: number;
  is_active: boolean;
  stock_qty: number | null;
}
export interface AdminRedemption {
  redemption_id: string;
  code: string;
  status: string;
  student_id: string;
  student_name: string;
  registration: string | null;
  class_id: string;
  class_name: string;
  reward_id: string;
  reward_name_snapshot: string | null;
  cost_points_snapshot: number | null;
  created_at: string;
  delivered_at: string | null;
  canceled_at: string | null;
  delivered_by_admin_id: string | null;
  delivered_by_admin_name: string | null;
}
type State<T> = { kind: 'loading' | 'loaded' | 'error'; rows: T[] };
@Injectable({ providedIn: 'root' })
export class AdminBinbazarRepository {
  readonly cap = inject(BinbazarPriceCapRepository);
  private readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  readonly products = signal<State<AdminProduct>>({ kind: 'loading', rows: [] });
  readonly redemptions = signal<State<AdminRedemption>>({ kind: 'loading', rows: [] });
  readonly submitting = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  readonly operation = signal<{
    action: 'product' | 'create-product' | 'deliver' | 'cancel';
    id: string;
  } | null>(null);
  private draft = { id: '', payload: '' };
  private context = this.auth.admin();
  private tickets = { products: 0, redemptions: 0 };
  constructor() {
    effect(() => {
      const context = this.auth.admin();
      if (context === this.context) return;
      this.context = context;
      this.tickets.products++;
      this.tickets.redemptions++;
      this.products.set({ kind: 'loading', rows: [] });
      this.redemptions.set({ kind: 'loading', rows: [] });
      this.operation.set(null);
      this.submitting.set(false);
      this.error.set('');
      this.notice.set('');
      this.draft = { id: '', payload: '' };
    });
  }
  async load(domain: 'products' | 'redemptions') {
    const admin = this.auth.admin(),
      ticket = ++this.tickets[domain];
    this[domain].set({ kind: 'loading', rows: [] });
    if (!admin || !['ADMIN_B', 'ADMIN_C'].includes(admin.role)) return;
    try {
      const client = await this.gateway.getClient();
      const result = await client.rpc(
        domain === 'products' ? 'get_admin_binbazar_products_v1' : 'get_admin_redemptions_v1',
      );
      if (result.error || !Array.isArray(result.data)) throw result.error;
      if (ticket === this.tickets[domain] && this.auth.admin() === admin)
        this[domain].set({ kind: 'loaded', rows: result.data });
    } catch {
      if (ticket === this.tickets[domain] && this.auth.admin() === admin)
        this[domain].set({ kind: 'error', rows: [] });
    }
  }
  open(action: 'product' | 'create-product' | 'deliver' | 'cancel', id: string) {
    if (this.submitting()) return;
    this.error.set('');
    this.notice.set('');
    this.operation.set({ action, id });
  }
  create() {
    if (this.submitting() || this.cap.state().kind !== 'loaded' || this.cap.state().value === null)
      return;
    this.draft = { id: crypto.randomUUID(), payload: '' };
    this.open('create-product', this.draft.id);
  }
  close() {
    if (!this.submitting()) this.operation.set(null);
  }
  async mutate(payload: Record<string, unknown> = {}) {
    const op = this.operation(),
      admin = this.auth.admin();
    if (!op || !admin || this.submitting()) return;
    if (op.action === 'create-product') {
      const semantic = JSON.stringify(payload);
      if (this.draft.payload && this.draft.payload !== semantic)
        this.draft.id = crypto.randomUUID();
      this.draft.payload = semantic;
      this.operation.set({ ...op, id: this.draft.id });
    }
    this.submitting.set(true);
    this.error.set('');
    this.notice.set('');
    try {
      const client = await this.gateway.getClient();
      const result = await client.rpc(
        op.action === 'create-product'
          ? 'create_admin_binbazar_product_v1'
          : op.action === 'product'
            ? 'update_admin_binbazar_product_v1'
            : op.action === 'deliver'
              ? 'deliver_admin_redemption_v1'
              : 'cancel_admin_redemption_v1',
        op.action === 'create-product'
          ? { p_reward_id: this.draft.id, ...payload }
          : op.action === 'product'
            ? { p_reward_id: op.id, ...payload }
            : { p_redemption_id: op.id },
      );
      if (result.error) throw result.error;
      if (this.auth.admin() !== admin) return;
      this.operation.set(null);
      this.notice.set(
        op.action === 'create-product'
          ? 'Produto cadastrado.'
          : op.action === 'product'
            ? 'Produto atualizado.'
            : op.action === 'deliver'
              ? 'Resgate entregue.'
              : 'Resgate cancelado.',
      );
      await Promise.all([this.load('products'), this.load('redemptions'), this.cap.load()]);
    } catch (e) {
      if (this.auth.admin() !== admin) return;
      const code = (e as { code?: string })?.code;
      const message = (e as { message?: string })?.message;
      if (message?.startsWith('BINBAZAR_PRICE_CAP_') || message === 'ADMIN_PRODUCT_ID_CONFLICT') {
        this.error.set(
          message === 'BINBAZAR_PRICE_CAP_EXCEEDED'
            ? 'Preço acima do teto global vigente.'
            : message === 'ADMIN_PRODUCT_ID_CONFLICT'
              ? 'Conflito: UUID de criação reutilizado com dados diferentes.'
              : 'Teto indisponível: ADMIN_A precisa configurar o limite.',
        );
        await this.cap.load();
        return;
      }
      this.error.set(
        code === '55000'
          ? 'Conflito: o resgate já foi concluído. Atualize a lista.'
          : code === 'P0001'
            ? 'Resgate histórico sem snapshot: cancelamento indisponível.'
            : 'Não foi possível concluir. Confira a conexão e tente novamente.',
      );
      if (code === '55000') await this.load('redemptions');
    } finally {
      if (this.auth.admin() === admin) this.submitting.set(false);
    }
  }
}
