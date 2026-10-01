import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminStore } from '../core/admin-store';
const defs: Record<string, { title: string; icon: string; submit: string }> = {
  'mission-create': { title: 'Criar missão global', icon: 'flag', submit: 'Criar missão' },
  'mission-edit': { title: 'Editar missão global', icon: 'flag', submit: 'Salvar missão' },
  'economy-edit': {
    title: 'Editar regra econômica',
    icon: 'sliders-horizontal',
    submit: 'Salvar regra',
  },
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
            @if (op.action.startsWith('mission-')) {
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
    return a === 'student-view';
  }
  idx() {
    return this.store.activeOperation()?.index ?? 0;
  }
  key() {
    return this.store.activeOperation()?.key;
  }
  mission() {
    return this.store.missions()[this.idx()];
  }
  economy() {
    return this.store.economySettings()[this.idx()];
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
