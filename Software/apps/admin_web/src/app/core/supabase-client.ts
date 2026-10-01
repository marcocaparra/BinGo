import { Injectable } from '@angular/core';
import type { SupabaseClient } from '@supabase/supabase-js';

@Injectable({ providedIn: 'root' })
export class AdminSupabaseClient {
  private client?: Promise<SupabaseClient>;

  getClient(): Promise<SupabaseClient> {
    return (this.client ??= this.configure().catch((error) => {
      this.client = undefined;
      throw error;
    }));
  }

  private async configure(): Promise<SupabaseClient> {
    const response = await fetch('supabase-config.json', {
      cache: 'no-store',
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok)
      throw new Error('Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY em supabase-config.json.');
    const config = await response.json();
    const url = config.SUPABASE_URL;
    const key = config.SUPABASE_PUBLISHABLE_KEY;
    if (typeof url !== 'string' || typeof key !== 'string' || !key.trim()) {
      throw new Error('Configuração pública do Supabase incompleta.');
    }
    const parsedUrl = new URL(url);
    if (!['http:', 'https:'].includes(parsedUrl.protocol))
      throw new Error('URL Supabase inválida.');
    // Aceita publishable moderna ou JWT anon. Recusa chaves tecnicas por engano.
    if (!key.startsWith('sb_publishable_')) {
      let role: unknown;
      try {
        role = JSON.parse(atob(key.split('.')[1])).role;
      } catch {
        /* fail-closed */
      }
      if (role !== 'anon') throw new Error('Use somente uma chave pública publishable/anon.');
    }
    const { createClient } = await import('@supabase/supabase-js');
    return createClient(url, key, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        storageKey: 'bingo.admin.auth',
      },
      global: {
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            signal: init?.signal
              ? AbortSignal.any([init.signal, AbortSignal.timeout(15000)])
              : AbortSignal.timeout(15000),
          }),
      },
    });
  }
}
