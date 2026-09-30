import { ChangeDetectionStrategy, Component, output } from '@angular/core';
import { AdminRole, ADMIN_ROLES } from '../admin-access';
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
        <div class="field">
          <label for="admin-role">Perfil demonstrativo</label
          ><select id="admin-role" name="role">
            @for (r of roles; track r.code) {
              <option [value]="r.code">{{ r.shortLabel }}</option>
            }</select
          ><small class="field-hint"
            >No produto real, o perfil virá da autenticação e será validado pelo backend.</small
          >
        </div>
        <div class="field">
          <label for="admin-email">E-mail institucional</label
          ><input id="admin-email" name="email" type="email" value="alencar@bingo.demo" required />
        </div>
        <div class="field">
          <label for="admin-password">Senha</label
          ><input id="admin-password" name="password" type="password" value="123456" required />
        </div>
        <button class="primary-button" type="submit">
          <span>Acessar o Admin</span><i data-lucide="arrow-right"></i>
        </button>
        <div class="access-note">
          <i data-lucide="shield-check"></i
          ><span
            ><strong>Ambiente demonstrativo.</strong>A autenticação segura será conectada ao
            contrato do backend.</span
          >
        </div>
      </form>
    </section>
  </main>`,
})
export class AccessComponent {
  readonly entered = output<AdminRole>();
  readonly roles = Object.values(ADMIN_ROLES);
  login(e: Event) {
    e.preventDefault();
    const f = new FormData(e.currentTarget as HTMLFormElement);
    this.entered.emit(f.get('role') as AdminRole);
  }
}
