import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminStore } from '../core/admin-store';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-deposits',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="period-metrics" aria-label="Quantidades de descartes">
      <article class="period-metric">
        <span><i data-lucide="database"></i></span>
        <div>
          <small>Total registrado</small
          ><strong>{{ store.discardStats.total.toLocaleString('pt-BR') }}</strong>
        </div>
      </article>
      <article class="period-metric">
        <span><i data-lucide="calendar-days"></i></span>
        <div>
          <small>Hoje</small><strong>{{ store.discardStats.today }}</strong>
        </div>
      </article>
      <article class="period-metric">
        <span><i data-lucide="calendar-range"></i></span>
        <div>
          <small>Nesta semana</small><strong>{{ store.discardStats.week }}</strong>
        </div>
      </article>
    </section>
    <div class="toolbar">
      <div class="filter-group">
        <button class="filter-button" type="button" aria-pressed="true">Hoje</button
        ><button class="filter-button" type="button" aria-pressed="false">Validados</button
        ><button class="filter-button" type="button" aria-pressed="false">Em revisão</button>
      </div>
      <button
        class="secondary-button"
        type="button"
        (click)="
          store.notify('A exportação será conectada quando o contrato do Admin estiver definido.')
        "
      >
        <i data-lucide="download"></i><span>Exportar visão</span>
      </button>
    </div>
    <section class="panel">
      <table class="data-table">
        <thead>
          <tr>
            <th>Horário</th>
            <th>Aluno ou perfil</th>
            <th>Turma</th>
            <th>Item</th>
            <th>Pontos</th>
            <th>Estado</th>
          </tr>
        </thead>
        <tbody>
          @for (d of store.deposits; track d.time) {
            <tr>
              <td>{{ d.time }}</td>
              <td>
                <strong>{{ d.student }}</strong>
              </td>
              <td>{{ d.className }}</td>
              <td>{{ d.item }}</td>
              <td>{{ d.points }}</td>
              <td>
                <span
                  class="tag"
                  [class.tag--success]="d.status === 'Validado'"
                  [class.tag--warning]="d.status === 'Revisão'"
                  [class.tag--blue]="d.status === 'Só turma'"
                  >{{ d.status }}</span
                >
              </td>
            </tr>
          }
        </tbody>
      </table>
    </section>`,
})
export class DepositsComponent {
  readonly store = inject(AdminStore);
}
@Component({
  selector: 'app-help',
  imports: [StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar">
      <div class="filter-group" aria-label="Filtros das solicitações">
        @for (f of filters; track f) {
          <button
            class="filter-button"
            type="button"
            [attr.aria-pressed]="store.helpFilter() === f"
            (click)="store.helpFilter.set(f)"
          >
            {{ f }}
          </button>
        }
      </div>
    </div>
    <section class="panel help-list">
      @for (item of filtered(); track item.id) {
        <article class="help-row">
          <span class="priority-line" [style.--accent]="priority(item.priority)"></span>
          <div class="row-copy">
            <strong>{{ item.place }}</strong
            ><span>{{ item.id }} · {{ item.reason }}</span>
          </div>
          <div class="row-meta">
            <strong>{{ item.priority }}</strong
            ><br />prioridade
          </div>
          <div class="row-meta">
            <span
              class="tag"
              [class.tag--success]="item.status === 'Resolvida'"
              [class.tag--blue]="item.status === 'Em atendimento'"
              [class.tag--warning]="item.status === 'Aguardando'"
              >{{ item.status }}</span
            ><br />{{ item.time }}
          </div>
          <button
            class="row-action"
            [class.row-action--primary]="item.status === 'Aguardando'"
            type="button"
            (click)="act(item.id)"
          >
            <i [attr.data-lucide]="item.status === 'Aguardando' ? 'hand' : 'arrow-up-right'"></i
            ><span>{{ item.status === 'Aguardando' ? 'Assumir' : 'Ver detalhes' }}</span>
          </button>
        </article>
      } @empty {
        <app-state-panel
          title="Nenhuma solicitação neste filtro"
          body="Escolha outro estado para continuar a consulta."
        />
      }
    </section>`,
})
export class HelpComponent {
  readonly store = inject(AdminStore);
  readonly filters = ['Todas', 'Aguardando', 'Em atendimento', 'Resolvida'];
  filtered() {
    const f = this.store.helpFilter();
    return f === 'Todas'
      ? this.store.helpRequests()
      : this.store.helpRequests().filter((x) => x.status === f);
  }
  priority(p: string) {
    return p === 'Alta' ? '#e52b3a' : p === 'Média' ? '#ffb020' : '#39d353';
  }
  act(id: string) {
    const req = this.store.helpRequests().find((x) => x.id === id);
    if (req?.status === 'Aguardando') {
      this.store.helpRequests.update((a) =>
        a.map((x) => (x.id === id ? { ...x, status: 'Em atendimento' } : x)),
      );
      this.store.notify(`${id} marcado em atendimento somente nesta demonstração.`);
    } else this.store.notify('Detalhes completos dependem do contrato de dados do backend.');
  }
}
