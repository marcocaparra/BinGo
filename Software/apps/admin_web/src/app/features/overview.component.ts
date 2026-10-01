import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, input, inject } from '@angular/core';
import { AdminRole } from '../admin-access';
import { AdminStore } from '../core/admin-store';
import { SummaryCardComponent } from '../shared/summary-card.component';
import { EntityRowComponent } from '../shared/entity-row.component';
@Component({
  selector: 'app-overview',
  imports: [NgTemplateOutlet, SummaryCardComponent, EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: ` @if (role() === 'ADMIN_A') {
      <section class="summary-grid" aria-label="Resumo global">
        <app-summary-card
          label="Escolas cadastradas"
          value="3"
          note="2 ativas · 1 em implantação"
          accent="#00aeef"
          icon="school"
        /><app-summary-card
          label="Administradores ativos"
          value="6"
          note="1 global · 5 escolares"
          accent="#8a2cff"
          icon="shield-user"
        /><app-summary-card
          label="Totens operacionais"
          value="6 de 8"
          note="1 com problema · 1 offline"
          accent="#39d353"
          icon="monitor-check"
        /><app-summary-card
          label="Missões globais"
          value="4"
          note="2 ativas · 2 programadas"
          accent="#ffb020"
          icon="flag"
        />
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Implantação das escolas</h2>
              <p>Estrutura geral sem filas operacionais locais.</p>
            </div>
            <button class="secondary-button" type="button" (click)="go('schools')">
              <span>Ver escolas</span><i data-lucide="arrow-right"></i>
            </button>
          </header>
          <div class="entity-list">
            @for (s of store.demoSchools(); track s.name) {
              <app-entity-row
                icon="school"
                [title]="s.name"
                [subtitle]="s.city"
                [meta]="s.students + ' · ' + s.machines"
                [status]="s.status"
              />
            }
          </div>
        </section>
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Saúde do ecossistema</h2>
              <p>Sinais que exigem acompanhamento do BinGo.</p>
            </div>
          </header>
          <div class="attention-list">
            <ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Totem Laboratório offline',
                b: 'Último sinal há 38 minutos no Colégio ENIAC.',
                c: '#e52b3a',
                i: 'wifi-off',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Escola Horizonte em implantação',
                b: 'Dois Totens aguardam vínculo operacional.',
                c: '#ffb020',
                i: 'school',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Ciclo SCR4P programado',
                b: 'Início previsto para a próxima segunda-feira.',
                c: '#8a2cff',
                i: 'flag',
              }"
            />
          </div>
        </section>
      </div>
    } @else if (role() === 'ADMIN_B') {
      <section class="summary-grid" aria-label="Resumo da escola">
        <app-summary-card
          label="Alunos ativos"
          value="427"
          note="1 aluno inativo"
          accent="#00aeef"
          icon="users"
        /><app-summary-card
          label="Turmas"
          value="14"
          note="9º A lidera a participação"
          accent="#8a2cff"
          icon="users-round"
        /><app-summary-card
          label="Pendências"
          [value]="String(store.demoPendingRedemptions() + 1)"
          note="3 resgates · 1 troca de turma"
          accent="#ffb020"
          icon="list-todo"
        /><app-summary-card
          label="Totens online"
          value="1 de 3"
          note="1 com problema · 1 offline"
          accent="#39d353"
          icon="monitor-check"
        />
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Pendências prioritárias</h2>
              <p>Decisões administrativas e entregas da escola.</p>
            </div>
            <button class="secondary-button" type="button" (click)="go('pending')">
              <span>Ver pendências</span><i data-lucide="arrow-right"></i>
            </button>
          </header>
          <div class="attention-list">
            <ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Troca de turma TT-032',
                b: 'Marina Santos aguarda decisão para o 9º B.',
                c: '#8a2cff',
                i: 'users-round',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: store.demoPendingRedemptions() + ' resgates pendentes',
                b: 'Produtos reservados aguardam entrega.',
                c: '#ffb020',
                i: 'ticket-check',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Totem Laboratório offline',
                b: 'Último sinal recebido há 38 minutos.',
                c: '#e52b3a',
                i: 'wifi-off',
              }"
            />
          </div>
        </section>
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Participação das turmas</h2>
              <p>Visão coletiva, sem exposição individual.</p>
            </div>
          </header>
          <div class="entity-list">
            @for (c of store.demoClasses(); track c.name) {
              <app-entity-row
                icon="users-round"
                [title]="c.name"
                [subtitle]="c.students"
                [meta]="c.xp + ' · ' + c.participation"
                [status]="c.status"
              />
            }
          </div>
        </section>
      </div>
    } @else {
      <section class="summary-grid" aria-label="Resumo operacional">
        <app-summary-card
          label="Descartes validados"
          [value]="store.discardStats.total.toLocaleString('pt-BR')"
          [note]="store.discardStats.today + ' hoje · ' + store.discardStats.week + ' nesta semana'"
          accent="#00aeef"
          icon="archive-restore"
        /><app-summary-card
          label="Ajudas abertas"
          [value]="String(store.openHelp())"
          note="1 aguardando · 1 em atendimento"
          accent="#e52b3a"
          icon="circle-help"
        /><app-summary-card
          label="Resgates pendentes"
          [value]="String(store.demoPendingRedemptions())"
          note="Aguardam validação da entrega"
          accent="#ffb020"
          icon="ticket-check"
        /><app-summary-card
          label="Totens online"
          value="1 de 3"
          note="1 com problema · 1 offline"
          accent="#39d353"
          icon="monitor-check"
        />
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Atividade recente</h2>
              <p>Eventos que ajudam a acompanhar a operação.</p>
            </div>
            <button class="secondary-button" type="button" (click)="go('deposits')">
              <span>Ver descartes</span><i data-lucide="arrow-right"></i>
            </button>
          </header>
          <div class="activity-list">
            @for (d of store.deposits.slice(0, 3); track d.time) {
              <article class="activity-row">
                <span class="activity-icon"><i [attr.data-lucide]="itemIcon(d.item)"></i></span>
                <div class="row-copy">
                  <strong>{{ d.student }}</strong
                  ><span>{{ d.item }} · {{ d.className }}</span>
                </div>
                <div class="row-meta">
                  <strong>{{ d.points }} pts</strong><br />{{ d.time }}
                </div>
                <span
                  class="tag"
                  [class.tag--success]="d.status === 'Validado'"
                  [class.tag--warning]="d.status === 'Revisão'"
                  [class.tag--blue]="d.status === 'Só turma'"
                  >{{ d.status }}</span
                >
              </article>
            }
          </div>
        </section>
        <section class="panel">
          <header class="panel-head">
            <div>
              <h2>Precisa de atenção</h2>
              <p>Prioridades para a equipe responsável.</p>
            </div>
          </header>
          <div class="attention-list">
            <ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Solicitação AJ-104',
                b: 'Item não reconhecido na Biblioteca.',
                c: '#e52b3a',
                i: 'circle-help',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: store.demoPendingRedemptions() + ' resgates pendentes',
                b: 'Recompensas aguardam confirmação de entrega.',
                c: '#ffb020',
                i: 'ticket-check',
              }"
            /><ng-container
              [ngTemplateOutlet]="attention"
              [ngTemplateOutletContext]="{
                t: 'Totem Laboratório offline',
                b: 'Último sinal recebido há 38 minutos.',
                c: '#e52b3a',
                i: 'wifi-off',
              }"
            />
          </div>
        </section>
      </div>
    }
    <ng-template #attention let-t="t" let-b="b" let-c="c" let-i="i"
      ><article class="attention-item" [style.--accent]="c">
        <span class="attention-icon"><i [attr.data-lucide]="i"></i></span>
        <div>
          <strong>{{ t }}</strong
          ><span>{{ b }}</span>
        </div>
      </article></ng-template
    >`,
})
export class OverviewComponent {
  readonly role = input.required<AdminRole>();
  readonly store = inject(AdminStore);
  readonly String = String;
  go(v: any) {
    this.store.view.set(v);
  }
  itemIcon(x: string) {
    return x === 'Celular'
      ? 'smartphone'
      : x === 'Cabo USB'
        ? 'cable'
        : x === 'Mouse'
          ? 'mouse'
          : 'battery-medium';
  }
}
