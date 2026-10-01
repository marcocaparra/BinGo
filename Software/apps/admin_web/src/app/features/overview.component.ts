import {
  ChangeDetectionStrategy,
  Component,
  effect,
  inject,
  input,
  untracked,
} from '@angular/core';
import { AdminRole, AdminView, canAccessView } from '../admin-access';
import { AdminStore } from '../core/admin-store';
import { AdminDashboardRepository } from '../core/admin-dashboard.repository';
import { SummaryCardComponent } from '../shared/summary-card.component';
import { EntityRowComponent } from '../shared/entity-row.component';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-overview',
  imports: [SummaryCardComponent, EntityRowComponent, StatePanelComponent],
  providers: [AdminDashboardRepository],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="toolbar toolbar--end">
      @for (link of links(); track link.view) {
        <button class="secondary-button" type="button" (click)="go(link.view)">
          {{ link.label }}
        </button>
      }
      <button
        class="secondary-button"
        type="button"
        [disabled]="dashboard.loading()"
        (click)="dashboard.load()"
      >
        Atualizar visão geral
      </button>
    </div>
    @if (dashboard.loading()) {
      <p class="contract-note" role="status">Carregando fotografia atual…</p>
    }
    @if (dashboard.failed()) {
      <p class="contract-note" role="alert">
        Algumas fontes estão indisponíveis. Seus números não foram substituídos por zero. Atualize
        para tentar novamente.
      </p>
    }
    <section class="summary-grid" aria-label="Resumo real">
      @for (card of dashboard.cards(); track card.label) {
        <app-summary-card
          [label]="card.label"
          [value]="card.value"
          [note]="card.note"
          accent="#00aeef"
          [icon]="card.icon"
        />
      }
    </section>
    <div class="dashboard-grid">
      @if (role() === 'ADMIN_A') {
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Escolas cadastradas</h2>
              <p>Contagens estruturais reais do ecossistema.</p>
            </div>
          </header>
          @if (dashboard.structure.schools().kind === 'loading') {
            <app-state-panel title="Carregando escolas" body="Consultando a estrutura global." />
          } @else if (dashboard.structure.schools().kind === 'error') {
            <app-state-panel
              title="Escolas indisponíveis"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (s of dashboard.structure.schools().rows; track s.school_id) {
                <app-entity-row
                  icon="school"
                  [title]="s.name"
                  [subtitle]="s.student_count + ' alunos · ' + s.class_count + ' turmas'"
                  [meta]="
                    s.admin_count +
                    ' administradores · ' +
                    s.machine_count +
                    ' máquinas cadastradas'
                  "
                />
              } @empty {
                <app-state-panel
                  title="Nenhuma escola cadastrada"
                  body="Novas escolas aparecerão aqui."
                />
              }
            </div>
          }
        </section>
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Contas administrativas</h2>
              <p>Identidade de domínio e vínculo de acesso.</p>
            </div>
          </header>
          @if (dashboard.structure.admins().kind === 'loading') {
            <app-state-panel
              title="Carregando administradores"
              body="Consultando as contas globais e escolares."
            />
          } @else if (dashboard.structure.admins().kind === 'error') {
            <app-state-panel
              title="Administradores indisponíveis"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (a of dashboard.structure.admins().rows.slice(0, 5); track a.admin_id) {
                <app-entity-row
                  icon="shield-user"
                  [title]="a.name"
                  [subtitle]="a.role + ' · ' + (a.school_name || 'Global')"
                  [meta]="
                    a.status +
                    ' · ' +
                    (a.access_linked ? 'Acesso vinculado' : 'Sem vínculo de acesso')
                  "
                />
              } @empty {
                <app-state-panel
                  title="Nenhum administrador"
                  body="Nenhuma conta retornada pela consulta."
                />
              }
            </div>
          }
        </section>
      } @else {
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>{{ role() === 'ADMIN_B' ? 'Pendências da escola' : 'Precisa de atenção' }}</h2>
              <p>Trocas, resgates e estoque consultados no backend.</p>
            </div>
          </header>
          <h3>
            {{
              role() === 'ADMIN_C' ? 'Minhas solicitações pendentes' : 'Trocas de turma pendentes'
            }}
          </h3>
          @if (dashboard.requests.state().kind === 'loading') {
            <app-state-panel
              title="Carregando solicitações"
              body="Consultando o escopo autorizado."
            />
          } @else if (dashboard.requests.state().kind === 'error') {
            <app-state-panel
              title="Solicitações indisponíveis"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (r of dashboard.pendingRequests().slice(0, 3); track r.request_id) {
                <app-entity-row
                  icon="send"
                  [title]="r.student_name"
                  [subtitle]="r.source_class_name + ' → ' + r.destination_class_name"
                  [meta]="
                    'Turma atual: ' + r.current_class_name + ' · ' + r.requested_by_admin_name
                  "
                />
                <p class="contract-note">
                  {{ date(r.created_at) }} · PENDING
                  @if (r.is_stale) {
                    · A turma atual mudou; aprovação bloqueada.
                  }
                </p>
              } @empty {
                <app-state-panel
                  title="Nenhuma troca pendente"
                  body="Não há solicitações PENDING neste escopo."
                />
              }
            </div>
          }
          <h3>Resgates aguardando entrega</h3>
          @if (dashboard.binbazar.redemptions().kind === 'loading') {
            <app-state-panel title="Carregando resgates" body="Consultando a escola vinculada." />
          } @else if (dashboard.binbazar.redemptions().kind === 'error') {
            <app-state-panel
              title="Resgates indisponíveis"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (r of dashboard.pendingRedemptions().slice(0, 3); track r.redemption_id) {
                <app-entity-row
                  icon="ticket-check"
                  [title]="r.reward_name_snapshot || 'Snapshot histórico indisponível'"
                  [subtitle]="r.student_name + ' · ' + r.code"
                  [meta]="
                    r.cost_points_snapshot === null
                      ? 'Preço histórico indisponível'
                      : r.cost_points_snapshot + ' BinCoins'
                  "
                />
                <p class="contract-note">{{ date(r.created_at) }} · PENDING</p>
              } @empty {
                <app-state-panel
                  title="Nenhum resgate pendente"
                  body="Não há pedidos aguardando entrega."
                />
              }
            </div>
          }
          <h3>Produtos ativos sem estoque</h3>
          @if (dashboard.binbazar.products().kind === 'loading') {
            <app-state-panel title="Carregando estoque" body="Consultando os produtos da escola." />
          } @else if (dashboard.binbazar.products().kind === 'error') {
            <app-state-panel
              title="Estoque indisponível"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (p of dashboard.outOfStock().slice(0, 3); track p.reward_id) {
                <app-entity-row
                  icon="package-open"
                  [title]="p.name"
                  subtitle="Estoque: 0 unidades"
                  [meta]="p.cost_points + ' BinCoins'"
                />
              } @empty {
                <app-state-panel
                  title="Nenhum produto ativo esgotado"
                  body="Nenhum produto ativo com estoque zero retornado."
                />
              }
            </div>
          }
        </section>
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Turmas da escola</h2>
              <p>Quantidade de alunos e XP atual.</p>
            </div>
          </header>
          @if (dashboard.school.state().kind === 'loading') {
            <app-state-panel
              title="Carregando alunos e turmas"
              body="Consultando a escola vinculada."
            />
          } @else if (dashboard.school.state().kind === 'error') {
            <app-state-panel
              title="Alunos e turmas indisponíveis"
              body="Não foi possível consultar esta fonte."
            />
          } @else {
            <div class="entity-list">
              @for (c of dashboard.school.state().classes; track c.class_id) {
                <app-entity-row
                  icon="users-round"
                  [title]="c.name"
                  [subtitle]="c.student_count + ' alunos'"
                  [meta]="c.points_class_balance + ' XP'"
                />
              } @empty {
                <app-state-panel
                  title="Nenhuma turma cadastrada"
                  body="Não há turmas nesta escola."
                />
              }
            </div>
          }
        </section>
      }
    </div>
    <p class="contract-note">
      Fotografia das leituras disponíveis. Atualize para consultar novamente; nenhum dado é alterado
      nesta tela.
    </p>
  `,
})
export class OverviewComponent {
  readonly role = input.required<AdminRole>();
  readonly store = inject(AdminStore);
  readonly dashboard = inject(AdminDashboardRepository);
  constructor() {
    effect(() => {
      if (this.dashboard.auth.admin()) untracked(() => void this.dashboard.load());
    });
  }
  links(): { view: AdminView; label: string }[] {
    return this.role() === 'ADMIN_A'
      ? [
          { view: 'schools', label: 'Ver escolas' },
          { view: 'administrators', label: 'Ver administradores' },
          { view: 'economy', label: 'Ver economia' },
        ]
      : [
          {
            view: this.role() === 'ADMIN_B' ? 'pending' : 'requests',
            label: this.role() === 'ADMIN_B' ? 'Ver pendências' : 'Ver minhas solicitações',
          },
          { view: 'redemptions', label: 'Ver resgates' },
          { view: 'products', label: 'Ver produtos' },
          { view: 'students', label: 'Ver alunos' },
        ];
  }
  go(view: AdminView) {
    if (canAccessView(this.role(), view)) this.store.view.set(view);
  }
  date(value: string) {
    return new Date(value).toLocaleString('pt-BR');
  }
}
