import { computed, effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';

export interface AdminDeposit {
  deposit_id: string;
  event_id: string;
  school_id: string;
  school_name: string;
  machine_id: string;
  machine_name: string;
  class_id: string;
  class_name: string;
  student_id: string | null;
  student_name: string | null;
  is_valid: boolean;
  detected_type: string | null;
  waste_category_code: string | null;
  category_source: string | null;
  bonus_rate_applied: number;
  bonus_bincoins_awarded: number;
  points_awarded_student: number;
  points_awarded_class: number;
  created_at: string;
}

type State = { kind: 'loading' | 'loaded' | 'error'; rows: AdminDeposit[] };

@Injectable({ providedIn: 'root' })
export class AdminDepositsRepository {
  readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  private context = this.auth.admin();
  private ticket = 0;
  private readonly snapshot = signal<State>({ kind: 'loading', rows: [] });
  readonly state = computed<State>(() =>
    this.auth.admin() === this.context ? this.snapshot() : { kind: 'loading', rows: [] },
  );

  constructor() {
    effect(() => this.syncContext());
  }

  private syncContext() {
    const admin = this.auth.admin();
    if (admin === this.context) return;
    this.context = admin;
    this.ticket++;
    this.snapshot.set({ kind: 'loading', rows: [] });
  }

  async load() {
    this.syncContext();
    const admin = this.auth.admin();
    const ticket = ++this.ticket;
    this.snapshot.set({ kind: 'loading', rows: [] });
    if (!admin) return;
    const current = () => this.auth.admin() === admin && ticket === this.ticket;
    try {
      const client = await this.gateway.getClient();
      if (!current()) return;
      const result = await client.rpc('get_admin_deposits_v1');
      if (result.error || !Array.isArray(result.data)) throw result.error;
      if (current()) this.snapshot.set({ kind: 'loaded', rows: result.data });
    } catch {
      if (current()) this.snapshot.set({ kind: 'error', rows: [] });
    }
  }
}
