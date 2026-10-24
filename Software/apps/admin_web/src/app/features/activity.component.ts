import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminDepositsRepository } from '../core/admin-deposits.repository';
import { AdminAuthService } from '../core/admin-auth.service';
import { AdminStore } from '../core/admin-store';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-deposits',
  imports: [DatePipe, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="secondary-button"
        type="button"
        [disabled]="repo.state().kind === 'loading'"
        (click)="repo.load()"
      >
        Atualizar descartes
      </button>
    </div>
    <p>Valores de BinCoins, bônus e XP são os snapshots gravados no descarte.</p>
    @if (repo.state().kind === 'loading') {
      <app-state-panel
        title="Carregando descartes"
        body="Consultando os registros disponíveis para sua conta."
      />
    } @else if (repo.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar descartes"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load()"
      />
    } @else if (repo.state().rows.length === 0) {
      <app-state-panel title="Nenhum descarte" body="Não há descartes registrados no seu escopo." />
    } @else {
      <section class="panel deposits-table">
        <table class="data-table">
          <thead>
            <tr>
              <th>Data e hora</th>
              @if (auth.admin()?.role === 'ADMIN_A') {
                <th>Escola</th>
              }
              <th>Aluno</th>
              <th>Turma</th>
              <th>Totem</th>
              <th>Tipo detectado</th>
              <th>Categoria</th>
              <th>Origem</th>
              <th>Validade</th>
              <th>BinCoins</th>
              <th>Bônus</th>
              <th>XP da turma</th>
            </tr>
          </thead>
          <tbody>
            @for (d of repo.state().rows; track d.deposit_id) {
              <tr>
                <td>{{ d.created_at | date: 'dd/MM/yyyy HH:mm:ss' }}</td>
                @if (auth.admin()?.role === 'ADMIN_A') {
                  <td>{{ d.school_name }}</td>
                }
                <td>
                  <strong>{{ d.student_name ?? 'Sem identificação' }}</strong>
                </td>
                <td>{{ d.class_name }}</td>
                <td>{{ d.machine_name }}</td>
                <td>{{ d.detected_type ?? 'Não informado' }}</td>
                <td>{{ d.waste_category_code ?? 'Sem categoria' }}</td>
                <td>{{ categorySource(d.category_source) }}</td>
                <td>
                  <span
                    class="tag"
                    [class.tag--success]="d.is_valid"
                    [class.tag--warning]="!d.is_valid"
                  >
                    {{ d.is_valid ? 'Válido' : 'Inválido' }}
                  </span>
                </td>
                <td>{{ d.points_awarded_student }}</td>
                <td>{{ d.bonus_bincoins_awarded }}</td>
                <td>{{ d.points_awarded_class }}</td>
              </tr>
            }
          </tbody>
        </table>
      </section>
    }`,
})
export class DepositsComponent {
  readonly repo = inject(AdminDepositsRepository);
  readonly auth = inject(AdminAuthService);

  constructor() {
    void this.repo.load();
  }

  categorySource(source: string | null) {
    return (
      {
        AI_CONFIRMED: 'IA confirmada',
        USER_CORRECTED: 'Corrigida pelo aluno',
        UNIDENTIFIED: 'Não identificada',
      }[source ?? ''] ?? 'Não informada'
    );
  }
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
