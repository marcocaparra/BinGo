import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminStore } from '../core/admin-store';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-redemptions',
  imports: [StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: ` <div class="toolbar">
      <div class="filter-group">
        @for (f of filters; track f) {
          <button
            class="filter-button"
            type="button"
            [attr.aria-pressed]="store.redemptionFilter() === f"
            (click)="store.redemptionFilter.set(f)"
          >
            {{ f }}
          </button>
        }
      </div>
      <span class="queue-summary"
        ><i data-lucide="clock-3"></i><strong>{{ store.pendingRedemptions() }}</strong> aguardando
        entrega</span
      >
    </div>
    <section class="panel redemption-list">
      @for (item of filtered(); track item.id) {
        <article class="redemption-row">
          <span class="redemption-icon"
            ><i [attr.data-lucide]="item.status === 'Pendente' ? 'ticket' : 'badge-check'"></i
          ></span>
          <div class="row-copy">
            <strong>{{ item.reward }}</strong
            ><span>{{ item.student }} · {{ item.className }}</span>
          </div>
          <div class="redemption-code">
            <small>Código</small><strong>{{ item.code }}</strong>
          </div>
          <div class="row-meta">
            <strong>{{ item.requestedAt }}</strong
            ><br />{{ item.expiresAt }}
          </div>
          <span
            class="tag"
            [class.tag--warning]="item.status === 'Pendente'"
            [class.tag--success]="item.status === 'Entregue'"
            [class.tag--danger]="item.status === 'Cancelado'"
            >{{ item.status }}</span
          >
          @if (item.status === 'Pendente') {
            <div class="row-actions">
              <button
                class="row-action row-action--primary"
                type="button"
                (click)="store.redemptionToDeliver.set(item.id)"
              >
                <i data-lucide="package-check"></i><span>Validar entrega</span></button
              ><button
                class="row-action"
                type="button"
                (click)="store.open('redemption-cancel', null, item.id)"
              >
                <i data-lucide="ticket-x"></i><span>Cancelar</span>
              </button>
            </div>
          } @else {
            <span class="delivered-label"
              ><i [attr.data-lucide]="item.status === 'Entregue' ? 'check' : 'x'"></i
              >{{ item.status === 'Entregue' ? 'Concluído' : 'Cancelado' }}</span
            >
          }
        </article>
      } @empty {
        <app-state-panel
          icon="badge-check"
          title="Fila concluída"
          body="Não há resgates aguardando entrega neste momento."
        />
      }
    </section>
    @if (selected(); as item) {
      <div class="dialog-backdrop" (click)="backdrop($event)">
        <section class="confirm-dialog" role="dialog" aria-modal="true">
          <span class="confirm-dialog-icon"><i data-lucide="package-check"></i></span>
          <p class="eyebrow">Simulação de resgate</p>
          <h2>Confirmar entrega?</h2>
          <p>
            Confira o código <strong>{{ item.code }}</strong> e entregue
            <strong>{{ item.reward }}</strong> para {{ item.student }}.
          </p>
          <div class="dialog-note">
            <i data-lucide="shield-check"></i>Esta ação será apenas demonstrativa até a integração
            com o backend.
          </div>
          <div class="dialog-actions">
            <button
              class="secondary-button"
              type="button"
              (click)="store.redemptionToDeliver.set(null)"
            >
              Cancelar</button
            ><button class="primary-button" type="button" (click)="deliver(item.id)">
              <i data-lucide="check"></i><span>Confirmar entrega</span>
            </button>
          </div>
        </section>
      </div>
    }`,
})
export class RedemptionsComponent {
  readonly store = inject(AdminStore);
  readonly filters = ['Pendentes', 'Entregues', 'Todas'];
  filtered() {
    const f = this.store.redemptionFilter();
    return f === 'Todas'
      ? this.store.redemptions()
      : this.store
          .redemptions()
          .filter((x) => x.status === (f === 'Pendentes' ? 'Pendente' : 'Entregue'));
  }
  selected() {
    return this.store.redemptions().find((x) => x.id === this.store.redemptionToDeliver());
  }
  backdrop(e: MouseEvent) {
    if (e.target === e.currentTarget) this.store.redemptionToDeliver.set(null);
  }
  deliver(id: string) {
    this.store.redemptions.update((a) =>
      a.map((x) => (x.id === id ? { ...x, status: 'Entregue', expiresAt: 'Entregue agora' } : x)),
    );
    this.store.redemptionToDeliver.set(null);
    this.store.notify(`${id} entregue somente nesta demonstração.`);
  }
}
