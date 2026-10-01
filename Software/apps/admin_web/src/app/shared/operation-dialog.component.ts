import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminStore } from '../core/admin-store';
const defs: Record<string, { title: string; icon: string; submit: string }> = {
  'admin-create': {
    title: 'Cadastrar administrador',
    icon: 'shield-plus',
    submit: 'Cadastrar acesso',
  },
  'admin-open': { title: 'Gerenciar administrador', icon: 'shield-user', submit: 'Salvar estado' },
  'school-create': { title: 'Cadastrar escola', icon: 'school', submit: 'Cadastrar escola' },
  'school-open': { title: 'Detalhes da escola', icon: 'school', submit: 'Salvar estado' },
  'mission-create': { title: 'Criar missão global', icon: 'flag', submit: 'Criar missão' },
  'mission-edit': { title: 'Editar missão global', icon: 'flag', submit: 'Salvar missão' },
  'economy-edit': {
    title: 'Editar regra econômica',
    icon: 'sliders-horizontal',
    submit: 'Salvar regra',
  },
  'machine-view': { title: 'Diagnóstico do Totem', icon: 'monitor-cog', submit: 'Fechar' },
};
@Component({
  selector: 'app-operation-dialog',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: ` @if (store.activeOperation(); as op) {
    <div class="dialog-backdrop" (click)="backdrop($event)">
      <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true">
        <span class="confirm-dialog-icon"><i [attr.data-lucide]="def().icon"></i></span>
        <p class="eyebrow">Dados demonstrativos</p>
        <h2 id="operation-dialog-title">{{ def().title }}</h2>
        <form (submit)="submit($event)">
          <div class="operation-fields">
            @if (op.action.startsWith('admin-')) {
              @let a = admin();
              <div class="field">
                <label for="op-name">Nome</label
                ><input id="op-name" name="name" [value]="a?.name || ''" required />
              </div>
              <div class="field">
                <label for="op-email">E-mail institucional</label
                ><input id="op-email" name="email" [value]="a?.email || ''" required />
              </div>
              <div class="field">
                <label for="op-role">Perfil</label
                ><select id="op-role" name="role">
                  @for (r of roleOptions(); track r) {
                    <option [selected]="r === (a?.role || roleOptions()[0])">{{ r }}</option>
                  }
                </select>
              </div>
              <div class="field">
                <label for="op-status">Estado do acesso</label
                ><select id="op-status" name="status">
                  <option [selected]="a?.status !== 'Inativo'">Ativo</option>
                  <option [selected]="a?.status === 'Inativo'">Inativo</option>
                </select>
              </div>
              <div class="dialog-note">
                <i data-lucide="shield-check"></i>O backend deverá validar escopo, impedir
                auto-inativação e registrar auditoria.
              </div>
            } @else if (op.action.startsWith('school-')) {
              @let s = school();
              <div class="field">
                <label for="op-name">Nome da escola</label
                ><input id="op-name" name="name" [value]="s?.name || ''" required />
              </div>
              <div class="field">
                <label for="op-city">Cidade e estado</label
                ><input id="op-city" name="city" [value]="s?.city || ''" required />
              </div>
              <div class="field">
                <label for="op-status">Estado</label
                ><select id="op-status" name="status">
                  @for (x of ['Implantação', 'Ativa', 'Inativa']; track x) {
                    <option [selected]="x === (s?.status || 'Implantação')">{{ x }}</option>
                  }
                </select>
              </div>
              <div class="dialog-note">
                <i data-lucide="database"></i>Vínculos, identificadores e isolamento dos dados serão
                definidos pelo backend.
              </div>
            } @else if (op.action.startsWith('mission-')) {
              @let m = mission();
              <div class="field">
                <label for="op-name">Nome da missão</label
                ><input id="op-name" name="name" [value]="m?.name || ''" required />
              </div>
              <div class="field">
                <label for="op-type">Tipo</label
                ><select id="op-type" name="type">
                  <option [selected]="m?.type !== 'Evento global'">Missão semanal</option>
                  <option [selected]="m?.type === 'Evento global'">Evento global</option>
                </select>
              </div>
              <div class="field">
                <label for="op-period">Período</label
                ><input id="op-period" name="period" [value]="m?.period || 'A definir'" required />
              </div>
              <div class="field">
                <label for="op-status">Estado</label
                ><select id="op-status" name="status">
                  @for (x of ['Pendente', 'Ativa', 'Encerrada']; track x) {
                    <option [selected]="x === (m?.status || 'Pendente')">{{ x }}</option>
                  }
                </select>
              </div>
            } @else if (op.action === 'economy-edit') {
              @let e = economy();
              <div class="operation-summary">
                <strong>{{ e?.title }}</strong
                ><span>{{ e?.description }}</span>
              </div>
              <div class="field">
                <label for="op-value">Valor em {{ e?.unit }}</label
                ><input id="op-value" name="value" [value]="e?.value || ''" required />
              </div>
              <div class="dialog-note">
                <i data-lucide="history"></i>A regra futura não poderá recalcular registros já
                confirmados.
              </div>
            } @else if (op.action === 'machine-view') {
              @let m = machine();
              <div class="operation-summary">
                <strong>{{ m?.name }}</strong
                ><span>{{ m?.code }} · {{ m?.status }}</span
                ><small>Última comunicação: {{ m?.lastSeen }}</small>
              </div>
              <div class="diagnostic-grid">
                <div class="machine-metric">
                  <small>Câmera</small><strong>{{ m?.camera }}</strong>
                </div>
                <div class="machine-metric">
                  <small>Porta</small><strong>{{ m?.door }}</strong>
                </div>
                <div class="machine-metric">
                  <small>Versão</small><strong>{{ m?.version }}</strong>
                </div>
              </div>
              <div class="dialog-note">
                <i data-lucide="radio"></i>Telemetria detalhada e comandos remotos dependem do
                serviço do Totem.
              </div>
            }
          </div>
          <div class="dialog-actions">
            <button class="secondary-button" type="button" (click)="store.close()">
              {{ viewOnly() ? 'Fechar' : 'Cancelar' }}
            </button>
            @if (!viewOnly()) {
              <button class="primary-button" type="submit">
                <i data-lucide="check"></i><span>{{ def().submit }}</span>
              </button>
            }
          </div>
        </form>
      </section>
    </div>
  }`,
})
export class OperationDialogComponent {
  readonly store = inject(AdminStore);
  def() {
    return (
      defs[this.store.activeOperation()!.action] || {
        title: 'Fluxo preparado',
        icon: 'panels-top-left',
        submit: 'Fechar',
      }
    );
  }
  viewOnly() {
    const a = this.store.activeOperation()?.action;
    return a === 'student-view' || a === 'machine-view';
  }
  idx() {
    return this.store.activeOperation()?.index ?? 0;
  }
  key() {
    return this.store.activeOperation()?.key;
  }
  admin() {
    return this.store.administrators().find((x) => x.email === this.key());
  }
  school() {
    return this.store.schools().find((x) => x.name === this.key());
  }
  mission() {
    return this.store.missions()[this.idx()];
  }
  economy() {
    return this.store.economySettings()[this.idx()];
  }
  machine() {
    return this.store.machines.find((x) => x.code === this.key());
  }
  roleOptions() {
    return this.store.role() === 'ADMIN_B' ? ['ADMIN_C'] : ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'];
  }
  clean(v: string | undefined, s: string) {
    return v?.replace(s, '');
  }
  backdrop(e: MouseEvent) {
    if (e.target === e.currentTarget) this.store.close();
  }
  submit(e: Event) {
    e.preventDefault();
    this.store.submit(e.currentTarget as HTMLFormElement);
  }
}
