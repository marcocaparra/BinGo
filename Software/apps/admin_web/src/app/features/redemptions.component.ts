import { ChangeDetectionStrategy, Component, inject, input, signal } from '@angular/core';
import { AdminBinbazarRepository } from '../core/admin-binbazar.repository';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-redemptions',
  imports: [StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (!compact()) {
      <div class="toolbar">
        <div class="filter-group">
          @for (f of filters; track f) {
            <button
              class="filter-button"
              type="button"
              [attr.aria-pressed]="filter() === f"
              (click)="filter.set(f)"
            >
              {{ f }}
            </button>
          }
        </div>
        <label
          >Código ou aluno
          <input aria-label="Código ou aluno" (input)="search.set($any($event.target).value)"
        /></label>
      </div>
    }
    @if (repo.notice()) {
      <p role="status">{{ repo.notice() }}</p>
    }
    @if (repo.redemptions().kind === 'loading') {
      <app-state-panel title="Carregando resgates" body="Consultando a escola vinculada." />
    } @else if (repo.redemptions().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar resgates"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load('redemptions')"
      />
    } @else {
      <section class="panel redemption-list">
        @for (r of filtered(); track r.redemption_id) {
          <article class="redemption-row">
            <span class="redemption-icon"><i data-lucide="ticket"></i></span>
            <div class="row-copy">
              <strong>{{ r.reward_name_snapshot || 'Snapshot histórico indisponível' }}</strong
              ><span
                >{{ r.student_name }} · {{ r.registration || 'Sem matrícula' }} ·
                {{ r.class_name }}</span
              ><small>{{
                r.cost_points_snapshot === null
                  ? 'Preço histórico indisponível'
                  : r.cost_points_snapshot + ' BinCoins'
              }}</small>
            </div>
            <div class="redemption-code">
              <small>Código interno</small><strong>{{ r.code }}</strong>
            </div>
            <div class="row-meta">
              {{ date(r.created_at) }}
              @if (r.delivered_at) {
                <br />Entregue {{ date(r.delivered_at) }} · {{ r.delivered_by_admin_name }}
              }
              @if (r.canceled_at) {
                <br />Cancelado {{ date(r.canceled_at) }}
              }
            </div>
            <span
              class="tag"
              [class.tag--warning]="r.status === 'PENDING'"
              [class.tag--success]="r.status === 'DELIVERED'"
              >{{ label(r.status) }}</span
            >
            @if (r.status === 'PENDING') {
              <div class="row-actions">
                <button
                  class="row-action row-action--primary"
                  type="button"
                  (click)="repo.open('deliver', r.redemption_id)"
                >
                  Validar entrega</button
                ><button
                  class="row-action"
                  type="button"
                  (click)="repo.open('cancel', r.redemption_id)"
                >
                  Cancelar
                </button>
              </div>
            }
          </article>
        } @empty {
          <app-state-panel title="Nenhum resgate" body="Não há resgates neste filtro." />
        }
      </section>
    }
    @if (selected(); as r) {
      <div class="dialog-backdrop">
        <section class="confirm-dialog" role="dialog" aria-modal="true">
          <h2>
            {{
              repo.operation()?.action === 'deliver'
                ? 'Confirmar entrega?'
                : 'Cancelar resgate reservado'
            }}
          </h2>
          <p>
            {{ r.student_name }} · {{ r.reward_name_snapshot || 'Snapshot indisponível' }} ·
            <strong>{{ r.code }}</strong>
          </p>
          <p class="dialog-note">
            {{
              repo.operation()?.action === 'deliver'
                ? 'Confira o aluno e o pedido antes da entrega. O código é somente um identificador administrativo.'
                : 'O cancelamento devolve os BinCoins debitados e restaura o estoque reservado quando aplicável.'
            }}
          </p>
          @if (repo.error()) {
            <p role="alert">{{ repo.error() }}</p>
          }
          <div class="dialog-actions">
            <button
              class="secondary-button"
              type="button"
              [disabled]="repo.submitting()"
              (click)="repo.close()"
            >
              Voltar</button
            ><button
              class="primary-button"
              type="button"
              [disabled]="repo.submitting()"
              (click)="repo.mutate()"
            >
              {{
                repo.submitting()
                  ? 'Processando…'
                  : repo.operation()?.action === 'deliver'
                    ? 'Confirmar entrega'
                    : 'Cancelar resgate'
              }}
            </button>
          </div>
        </section>
      </div>
    }`,
})
export class RedemptionsComponent {
  readonly repo = inject(AdminBinbazarRepository);
  readonly compact = input(false);
  readonly filter = signal('Pendentes');
  readonly search = signal('');
  readonly filters = ['Pendentes', 'Entregues', 'Cancelados', 'Todas'];
  constructor() {
    void this.repo.load('redemptions');
  }
  filtered() {
    const status = this.compact()
      ? 'PENDING'
      : (
          { Pendentes: 'PENDING', Entregues: 'DELIVERED', Cancelados: 'CANCELED' } as Record<
            string,
            string
          >
        )[this.filter()];
    const query = this.search().trim().toLowerCase();
    return this.repo
      .redemptions()
      .rows.filter(
        (r) =>
          (!status || r.status === status) &&
          [r.code, r.student_name, r.registration || ''].some((v) =>
            v.toLowerCase().includes(query),
          ),
      );
  }
  selected() {
    const op = this.repo.operation();
    return op && ['deliver', 'cancel'].includes(op.action)
      ? this.repo.redemptions().rows.find((r) => r.redemption_id === op.id)
      : null;
  }
  label(status: string) {
    return (
      (
        { PENDING: 'Pendente', DELIVERED: 'Entregue', CANCELED: 'Cancelado' } as Record<
          string,
          string
        >
      )[status] || 'Registro histórico'
    );
  }
  date(value: string) {
    return new Date(value).toLocaleString('pt-BR');
  }
}
