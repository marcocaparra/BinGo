import { computed, effect, inject, Injectable, signal } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminSupabaseClient } from './supabase-client';

export interface AdminMachine {
  machine_id: string;
  school_id: string;
  school_name: string;
  name: string;
  status: 'ONLINE' | 'OFFLINE' | 'MAINTENANCE' | 'OUT_OF_SERVICE';
  firmware_version: string | null;
  last_seen: string | null;
  bin_full: boolean;
  camera_ok: boolean;
  net_ok: boolean;
}
type State = { kind: 'loading' | 'loaded' | 'error'; rows: AdminMachine[] };
@Injectable({ providedIn: 'root' })
export class AdminMachinesRepository {
  readonly auth = inject(AdminAuthService);
  private readonly gateway = inject(AdminSupabaseClient);
  private context = this.auth.admin();
  private ticket = 0;
  private readonly snapshot = signal<State>({ kind: 'loading', rows: [] });
  // Remove dados imediatamente quando a identidade muda, inclusive antes do effect.
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
    const admin = this.auth.admin(),
      ticket = ++this.ticket;
    this.snapshot.set({ kind: 'loading', rows: [] });
    if (!admin) return;
    const current = () => this.auth.admin() === admin && ticket === this.ticket;
    try {
      const client = await this.gateway.getClient();
      if (!current()) return;
      const result = await client.rpc('get_admin_machines_v1');
      if (result.error || !Array.isArray(result.data)) throw result.error;
      if (current()) this.snapshot.set({ kind: 'loaded', rows: result.data });
    } catch {
      if (current()) this.snapshot.set({ kind: 'error', rows: [] });
    }
  }
}
