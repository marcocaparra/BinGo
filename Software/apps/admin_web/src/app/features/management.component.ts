import { BinbazarPriceCapComponent } from './binbazar-price-cap.component';
import { RedemptionsComponent } from './redemptions.component';
export { ProductsComponent } from './products.component';
import { ChangeDetectionStrategy, Component, inject, input } from '@angular/core';
import { AdminRole } from '../admin-access';
import { StatePanelComponent } from '../shared/state-panel.component';
import { AdminSchoolRepository } from '../core/admin-school.repository';
import { AdminStore } from '../core/admin-store';
import { ClassRequestsComponent } from './class-requests.component';
import { EntityRowComponent } from '../shared/entity-row.component';
export { SchoolsComponent, AdministratorsComponent } from './admin-structure.component';
@Component({
  selector: 'app-students',
  imports: [StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (school.state().kind === 'loading') {
      <app-state-panel title="Carregando alunos…" body="Consultando a escola vinculada." />
    } @else if (school.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar alunos"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="school.load()"
      />
    } @else {
      @if (role() === 'ADMIN_B') {
        <div class="toolbar toolbar--end">
          <button
            class="primary-button compact-button"
            type="button"
            (click)="school.open('student-create')"
          >
            <i data-lucide="plus"></i><span>Cadastrar aluno</span>
          </button>
        </div>
      }
      @if (!school.state().students.length) {
        <app-state-panel
          title="Nenhum aluno cadastrado"
          body="Os alunos desta escola aparecerão aqui."
        />
      } @else {
        <section class="panel">
          <table class="data-table">
            <thead>
              <tr>
                <th>Aluno</th>
                <th>RA ou matrícula</th>
                <th>Turma</th>
                <th>BinCoins</th>
                <th>XP da turma</th>
                <th>Estado</th>
                <th>{{ role() === 'ADMIN_B' ? 'Ação' : 'Acesso' }}</th>
              </tr>
            </thead>
            <tbody>
              @for (s of school.state().students; track s.student_id) {
                <tr>
                  <td>
                    <strong>{{ s.name }}</strong
                    ><br /><small>{{ s.email || 'Email não informado' }}</small>
                  </td>
                  <td>{{ s.registration || 'Não informada' }}</td>
                  <td>{{ s.class_name }}</td>
                  <td>{{ s.points_student_balance }}</td>
                  <td>{{ s.class_points_balance }}</td>
                  <td>
                    <span
                      class="tag"
                      [class.tag--danger]="s.status === 'INACTIVE'"
                      [class.tag--success]="s.status === 'ACTIVE'"
                      >{{ s.status === 'ACTIVE' ? 'Ativo' : 'Inativo' }}</span
                    >
                  </td>
                  <td>
                    <button
                      class="row-action"
                      type="button"
                      (click)="
                        school.open(
                          role() === 'ADMIN_B' ? 'student-edit' : 'student-view',
                          s.student_id
                        )
                      "
                    >
                      <i [attr.data-lucide]="role() === 'ADMIN_B' ? 'square-pen' : 'eye'"></i
                      ><span>{{ role() === 'ADMIN_B' ? 'Editar' : 'Consultar' }}</span>
                    </button>
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </section>
      }
    }
    @if (school.notice()) {
      <p role="status" class="contract-note">{{ school.notice() }}</p>
    }
    <p class="contract-note">
      <i data-lucide="shield-check"></i>Saldo, PIN, senha e identificadores internos nunca são
      editados manualmente.
    </p>`,
})
export class StudentsComponent {
  readonly school = inject(AdminSchoolRepository);
  role = input.required<AdminRole>();
  constructor() {
    void this.school.load();
  }
}
@Component({
  selector: 'app-classes',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (school.state().kind === 'loading') {
      <app-state-panel title="Carregando turmas…" body="Consultando a escola vinculada." />
    } @else if (school.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar turmas"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="school.load()"
      />
    } @else {
      <div class="toolbar toolbar--end">
        <button
          class="primary-button compact-button"
          type="button"
          (click)="school.open('class-create')"
        >
          <i data-lucide="plus"></i><span>Criar turma</span>
        </button>
      </div>
      @if (!school.state().classes.length) {
        <app-state-panel
          title="Nenhuma turma cadastrada"
          body="As turmas desta escola aparecerão aqui."
        />
      } @else {
        <section class="panel entity-list">
          @for (c of school.state().classes; track c.class_id) {
            <app-entity-row
              icon="users-round"
              [title]="c.name"
              [subtitle]="c.segment + ' · ' + c.grade + ' · ' + c.student_count + ' alunos'"
              [meta]="c.points_class_balance + ' XP'"
              actionLabel="Editar"
              actionIcon="square-pen"
              (action)="school.open('class-edit', c.class_id)"
            />
          }
        </section>
      }
    }
    @if (school.notice()) {
      <p role="status" class="contract-note">{{ school.notice() }}</p>
    }`,
})
export class ClassesComponent {
  readonly school = inject(AdminSchoolRepository);
  constructor() {
    void this.school.load();
  }
}
@Component({
  selector: 'app-pending',
  imports: [RedemptionsComponent, ClassRequestsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="pending-groups">
    <div class="panel">
      <header class="panel-head">
        <div>
          <h2>Trocas de turma</h2>
          <p>Exigem decisão de um Admin B.</p>
        </div>
      </header>
      <p class="contract-note">Dados reais da escola vinculada</p>
      <app-class-requests [manage]="true" />
    </div>
    <div class="panel">
      <header class="panel-head">
        <div>
          <h2>Resgates reservados</h2>
          <p>Dados reais da escola vinculada</p>
          <p>Produtos aguardando entrega ou cancelamento.</p>
        </div>
        <button class="secondary-button" type="button" (click)="store.view.set('redemptions')">
          <span>Ver fila</span><i data-lucide="arrow-right"></i>
        </button>
      </header>
      <app-redemptions [compact]="true" />
    </div>
  </section>`,
})
export class PendingComponent {
  readonly store = inject(AdminStore);
}
@Component({
  selector: 'app-requests',
  imports: [ClassRequestsComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="panel"><app-class-requests /></section>`,
})
export class RequestsComponent {}
@Component({
  selector: 'app-missions',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (role() === 'ADMIN_A') {
      <div class="toolbar toolbar--end">
        <button
          class="primary-button compact-button"
          type="button"
          (click)="store.open('mission-create')"
        >
          <i data-lucide="plus"></i><span>Criar missão global</span>
        </button>
      </div>
    }
    <section class="panel entity-list">
      @for (m of store.missions(); track m.name; let i = $index) {
        <app-entity-row
          [icon]="m.type === 'Evento global' ? 'shield' : 'flag'"
          [title]="m.name"
          [subtitle]="m.type + ' · todas as escolas'"
          [meta]="m.period"
          [status]="m.status"
          [actionLabel]="role() === 'ADMIN_A' ? 'Editar' : ''"
          actionIcon="square-pen"
          (action)="store.open('mission-edit', i)"
        />
      }
    </section>
    @if (role() !== 'ADMIN_A') {
      <p class="contract-note">
        <i data-lucide="eye"></i>A escola consulta as Missões globais, mas não cria Missões no V1.
      </p>
    }`,
})
export class MissionsComponent {
  readonly store = inject(AdminStore);
  role = input.required<AdminRole>();
}
@Component({
  selector: 'app-economy',
  imports: [BinbazarPriceCapComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<app-binbazar-price-cap />
    <p class="contract-note">Outras configurações — Dados demonstrativos</p>
    <section class="settings-grid">
      @for (s of store.economySettings(); track s.title; let i = $index) {
        <article class="setting-card">
          <span class="activity-icon"><i [attr.data-lucide]="s.icon"></i></span>
          <div>
            <small>{{ s.title }}</small
            ><strong>{{ s.value }} {{ s.unit }}</strong>
            <p>{{ s.description }}</p>
          </div>
          <button class="row-action" type="button" (click)="store.open('economy-edit', i)">
            <i data-lucide="square-pen"></i><span>Editar</span>
          </button>
        </article>
      }
    </section>
    <p class="contract-note">
      <i data-lucide="history"></i>Alterações futuras não modificam descartes, resgates ou
      pontuações já registrados.
    </p>`,
})
export class EconomyComponent {
  readonly store = inject(AdminStore);
}
