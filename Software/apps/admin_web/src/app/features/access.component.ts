import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminAuthService } from '../core/admin-auth.service';
@Component({
  selector: 'app-access',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<main class="access-page">
    <section class="access-brand">
      <div class="brand-lockup">
        <img src="assets/brand/logo-bingo.png" alt="BinGo" /><span>Admin Lite</span>
      </div>
      <div class="access-copy">
        <p class="access-kicker">Operação escolar</p>
        <h1>Acompanhe o que acontece nos Totens.</h1>
        <p>
          Depósitos, pedidos de ajuda e estado dos equipamentos reunidos em uma visão direta para a
          equipe responsável.
        </p>
      </div>
      <div class="access-footnote">
        <i data-lucide="shield-check"></i>Ambiente interno do Colégio ENIAC
      </div>
    </section>
    <section class="access-panel-wrap">
      <form class="access-panel" (submit)="login($event)">
        <p class="eyebrow">Acesso técnico</p>
        <h2>Entrar no Admin</h2>
        <p>Use seu acesso autorizado para acompanhar a operação da escola.</p>
        @if (!auth.state().hasSession) {
          <div class="field">
            <label for="admin-email">E-mail institucional</label
            ><input
              id="admin-email"
              name="email"
              type="email"
              autocomplete="username"
              [disabled]="auth.busy()"
              required
            />
          </div>
          <div class="field">
            <label for="admin-password">Senha</label
            ><input
              id="admin-password"
              name="password"
              type="password"
              autocomplete="current-password"
              [disabled]="auth.busy()"
              required
            />
          </div>
          <button class="primary-button" type="submit" [disabled]="auth.busy()">
            <span>Acessar o Admin</span><i data-lucide="arrow-right"></i>
          </button>
        }
        @if (auth.state().message) {
          <p [attr.role]="auth.busy() ? 'status' : 'alert'" aria-live="polite">
            {{ auth.state().message }}
          </p>
        }
        @if (auth.state().kind === 'error') {
          <button class="secondary-button" type="button" (click)="auth.restore()">
            Tentar novamente
          </button>
        }
        @if (auth.state().hasSession) {
          <button
            class="text-button"
            type="button"
            [disabled]="auth.busy()"
            (click)="auth.logout()"
          >
            Sair
          </button>
        }
        <div class="access-note">
          <i data-lucide="shield-check"></i
          ><span
            ><strong>Acesso autenticado.</strong>Os dados e operações das demais telas continuam
            demonstrativos.</span
          >
        </div>
      </form>
    </section>
  </main>`,
})
export class AccessComponent {
  readonly auth = inject(AdminAuthService);
  login(e: Event) {
    e.preventDefault();
    const form = e.currentTarget as HTMLFormElement;
    const f = new FormData(form);
    void this.auth.login(String(f.get('email') ?? '').trim(), String(f.get('password') ?? ''));
    (form.elements.namedItem('password') as HTMLInputElement).value = '';
  }
}
