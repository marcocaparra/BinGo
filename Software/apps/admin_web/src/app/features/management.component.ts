import { ChangeDetectionStrategy, Component, inject, input } from '@angular/core';
import { AdminRole } from '../admin-access';
import { AdminStore } from '../core/admin-store';
import { EntityRowComponent } from '../shared/entity-row.component';
@Component({
  selector: 'app-schools',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        (click)="store.open('school-create')"
      >
        <i data-lucide="plus"></i><span>Cadastrar escola</span>
      </button>
    </div>
    <section class="panel entity-list">
      @for (s of store.schools(); track s.name) {
        <app-entity-row
          icon="school"
          [title]="s.name"
          [subtitle]="s.city"
          [meta]="s.students + ' · ' + s.machines"
          [status]="s.status"
          actionLabel="Abrir"
          (action)="store.open('school-open', null, s.name)"
        />
      }
    </section>`,
})
export class SchoolsComponent {
  readonly store = inject(AdminStore);
}
@Component({
  selector: 'app-administrators',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        (click)="store.open('admin-create')"
      >
        <i data-lucide="plus"></i
        ><span>{{ role() === 'ADMIN_B' ? 'Cadastrar Admin C' : 'Cadastrar administrador' }}</span>
      </button>
    </div>
    <section class="panel entity-list">
      @for (a of visible(); track a.email) {
        <app-entity-row
          icon="shield-user"
          [title]="a.name"
          [subtitle]="a.email + ' · ' + a.scope"
          [meta]="a.role"
          [status]="a.status"
          actionLabel="Gerenciar"
          actionIcon="settings"
          (action)="store.open('admin-open', null, a.email)"
        />
      }
    </section>
    <p class="contract-note">
      <i data-lucide="history"></i>Contas são inativadas, nunca apagadas. Ninguém pode desativar a
      própria conta.
    </p>`,
})
export class AdministratorsComponent {
  readonly store = inject(AdminStore);
  role = input.required<AdminRole>();
  visible() {
    return this.role() === 'ADMIN_B'
      ? this.store.administrators().filter((a) => a.role === 'ADMIN_C')
      : this.store.administrators();
  }
}
@Component({
  selector: 'app-students',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (role() === 'ADMIN_B') {
      <div class="toolbar toolbar--end">
        <button
          class="primary-button compact-button"
          type="button"
          (click)="store.open('student-create')"
        >
          <i data-lucide="plus"></i><span>Cadastrar aluno</span>
        </button>
      </div>
    }
    <section class="panel">
      <table class="data-table">
        <thead>
          <tr>
            <th>Aluno</th>
            <th>RA ou matrícula</th>
            <th>Turma</th>
            <th>BinCoins</th>
            <th>Estado</th>
            <th>{{ role() === 'ADMIN_B' ? 'Ação' : 'Acesso' }}</th>
          </tr>
        </thead>
        <tbody>
          @for (s of store.students(); track s.registration; let i = $index) {
            <tr>
              <td>
                <strong>{{ s.name }}</strong
                ><br /><small>{{ s.email }}</small>
              </td>
              <td>{{ s.registration }}</td>
              <td>{{ s.className }}</td>
              <td>{{ s.balance }}</td>
              <td>
                <span
                  class="tag"
                  [class.tag--danger]="s.status === 'Inativo'"
                  [class.tag--success]="s.status !== 'Inativo'"
                  >{{ s.status }}</span
                >
              </td>
              <td>
                <button
                  class="row-action"
                  type="button"
                  (click)="store.open(role() === 'ADMIN_B' ? 'student-edit' : 'student-view', i)"
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
    <p class="contract-note">
      <i data-lucide="shield-check"></i>Saldo, PIN, senha e identificadores internos nunca são
      editados manualmente.
    </p>`,
})
export class StudentsComponent {
  readonly store = inject(AdminStore);
  role = input.required<AdminRole>();
}
@Component({
  selector: 'app-classes',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        (click)="store.open('class-create')"
      >
        <i data-lucide="plus"></i><span>Criar turma</span>
      </button>
    </div>
    <section class="panel entity-list">
      @for (c of store.classes(); track c.name; let i = $index) {
        <app-entity-row
          icon="users-round"
          [title]="c.name"
          [subtitle]="c.students"
          [meta]="c.xp + ' · ' + c.participation"
          [status]="c.status"
          actionLabel="Editar"
          actionIcon="square-pen"
          (action)="store.open('class-edit', i)"
        />
      }
    </section>`,
})
export class ClassesComponent {
  readonly store = inject(AdminStore);
}
@Component({
  selector: 'app-pending',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="pending-groups">
    <div class="panel">
      <header class="panel-head">
        <div>
          <h2>Trocas de turma</h2>
          <p>Exigem decisão de um Admin B.</p>
        </div>
        <span class="tag tag--warning">1 pendente</span>
      </header>
      <div class="entity-list">
        @for (r of store.classRequests(); track r.id; let i = $index) {
          <app-entity-row
            icon="users-round"
            [title]="r.student + ' · ' + r.id"
            [subtitle]="r.current + ' → ' + r.destination"
            [meta]="'Solicitado por ' + r.author"
            [status]="r.status"
            [actionLabel]="r.status === 'Pendente' ? 'Analisar' : ''"
            actionIcon="check-check"
            [primary]="true"
            (action)="store.open('request-review', i)"
          />
        }
      </div>
    </div>
    <div class="panel">
      <header class="panel-head">
        <div>
          <h2>Resgates reservados</h2>
          <p>Produtos aguardando entrega ou cancelamento.</p>
        </div>
        <button class="secondary-button" type="button" (click)="store.view.set('redemptions')">
          <span>Ver fila</span><i data-lucide="arrow-right"></i>
        </button>
      </header>
      <div class="entity-list">
        @for (r of pending(); track r.id) {
          <app-entity-row
            icon="ticket"
            [title]="r.reward"
            [subtitle]="r.student + ' · ' + r.className"
            [meta]="r.code"
            [status]="r.status"
          />
        }
      </div>
    </div>
  </section>`,
})
export class PendingComponent {
  readonly store = inject(AdminStore);
  pending() {
    return this.store.redemptions().filter((x) => x.status === 'Pendente');
  }
}
@Component({
  selector: 'app-requests',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        (click)="store.open('request-create')"
      >
        <i data-lucide="plus"></i><span>Solicitar troca de turma</span>
      </button>
    </div>
    <section class="panel entity-list">
      @for (r of store.classRequests(); track r.id; let i = $index) {
        <app-entity-row
          icon="send"
          [title]="r.student + ' · ' + r.id"
          [subtitle]="r.current + ' → ' + r.destination"
          [meta]="r.author"
          [status]="r.status"
          [actionLabel]="r.status === 'Pendente' ? 'Cancelar' : ''"
          actionIcon="x"
          (action)="store.open('request-cancel', i)"
        />
      }
    </section>
    <p class="contract-note">
      <i data-lucide="info"></i>A turma só muda depois da aprovação de um Admin B.
    </p>`,
})
export class RequestsComponent {
  readonly store = inject(AdminStore);
}
@Component({
  selector: 'app-products',
  imports: [EntityRowComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        (click)="store.open('product-create')"
      >
        <i data-lucide="plus"></i><span>Cadastrar produto</span>
      </button>
    </div>
    <section class="panel entity-list">
      @for (p of store.products(); track p.name; let i = $index) {
        <app-entity-row
          icon="package-open"
          [title]="p.name"
          [subtitle]="p.stock"
          [meta]="p.price"
          [status]="p.status"
          actionLabel="Editar"
          actionIcon="square-pen"
          (action)="store.open('product-edit', i)"
        />
      }
    </section>
    <p class="contract-note">
      <i data-lucide="badge-dollar-sign"></i>O preço deve respeitar o teto global definido pelo
      BinGo.
    </p>`,
})
export class ProductsComponent {
  readonly store = inject(AdminStore);
}
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
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="settings-grid">
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
