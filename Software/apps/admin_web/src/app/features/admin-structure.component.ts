import { ChangeDetectionStrategy, Component, inject, input, signal } from '@angular/core';
import { AdminRole } from '../admin-access';
import { AdminStructureRepository } from '../core/admin-structure.repository';
import { EntityRowComponent } from '../shared/entity-row.component';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-schools',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        [disabled]="repo.submitting()"
        (click)="repo.open('school-create')"
      >
        Cadastrar escola
      </button>
    </div>
    @if (repo.notice()) {
      <p role="status">{{ repo.notice() }}</p>
    }
    @if (repo.schools().kind === 'loading') {
      <app-state-panel title="Carregando escolas" body="Consultando o ecossistema." />
    } @else if (repo.schools().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar escolas"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load('schools')"
      />
    } @else {
      <section class="panel entity-list">
        @for (s of repo.schools().rows; track s.school_id) {
          <app-entity-row
            icon="school"
            [title]="s.name"
            [subtitle]="s.student_count + ' alunos · ' + s.class_count + ' turmas'"
            [meta]="s.admin_count + ' administradores · ' + s.machine_count + ' máquinas'"
          />
        } @empty {
          <app-state-panel title="Nenhuma escola" body="Não há escolas cadastradas." />
        }
      </section>
    }
    @if (repo.operation()?.kind === 'school-create') {
      <div class="dialog-backdrop">
        <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true">
          <h2>Cadastrar escola</h2>
          <form (submit)="save($event)">
            <div class="operation-fields">
              <div class="field">
                <label for="school-name">Nome da escola</label
                ><input id="school-name" name="name" required />
              </div>
            </div>
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
                Cancelar</button
              ><button class="primary-button" type="submit" [disabled]="repo.submitting()">
                {{ repo.submitting() ? 'Salvando…' : 'Cadastrar escola' }}
              </button>
            </div>
          </form>
        </section>
      </div>
    }`,
})
export class SchoolsComponent {
  readonly repo = inject(AdminStructureRepository);
  constructor() {
    void this.repo.load('schools');
  }
  save(e: Event) {
    e.preventDefault();
    void this.repo.save({
      p_name: String(new FormData(e.currentTarget as HTMLFormElement).get('name')),
    });
  }
}
@Component({
  selector: 'app-administrators',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        [disabled]="repo.submitting()"
        (click)="create()"
      >
        {{ role() === 'ADMIN_B' ? 'Cadastrar Admin C' : 'Cadastrar administrador' }}
      </button>
    </div>
    @if (repo.notice()) {
      <p role="status">{{ repo.notice() }}</p>
    }
    @if (repo.admins().kind === 'loading') {
      <app-state-panel
        title="Carregando administradores"
        body="Consultando as contas no seu escopo."
      />
    } @else if (repo.admins().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar administradores"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load('admins')"
      />
    } @else {
      <section class="panel entity-list">
        @for (a of repo.admins().rows; track a.admin_id) {
          <app-entity-row
            icon="shield-user"
            [title]="a.name"
            [subtitle]="a.email + ' · ' + (a.school_name || 'Global')"
            [meta]="
              a.role + ' · ' + (a.access_linked ? 'Acesso vinculado' : 'Sem vínculo de acesso')
            "
            [status]="a.status === 'ACTIVE' ? 'Ativo' : 'Inativo'"
            actionLabel="Gerenciar"
            actionIcon="settings"
            (action)="repo.open('admin-edit', a.admin_id)"
          />
        } @empty {
          <app-state-panel
            title="Nenhum administrador"
            body="Não há contas administrativas neste escopo."
          />
        }
      </section>
    }
    <p class="contract-note">
      Contas são inativadas, nunca apagadas. Ninguém pode desativar a própria conta. O vínculo de
      acesso é provisionado separadamente.
    </p>
    @if (editing()) {
      @let a = selected();
      <div class="dialog-backdrop">
        <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true">
          <h2>{{ a ? 'Gerenciar administrador' : 'Cadastrar administrador' }}</h2>
          <form (submit)="save($event)">
            <div class="operation-fields">
              <div class="field">
                <label for="managed-name">Nome completo</label
                ><input id="managed-name" name="name" [value]="a?.name || ''" required />
              </div>
              <div class="field">
                <label for="managed-email">E-mail institucional</label
                ><input
                  id="managed-email"
                  name="email"
                  type="email"
                  [value]="a?.email || ''"
                  required
                />
              </div>
              @if (!a) {
                @if (role() === 'ADMIN_A') {
                  <div class="field">
                    <label for="managed-role">Perfil</label
                    ><select
                      id="managed-role"
                      name="role"
                      (change)="newRole.set($any($event.target).value)"
                    >
                      <option value="ADMIN_A">ADMIN_A</option>
                      <option value="ADMIN_B">ADMIN_B</option>
                      <option value="ADMIN_C">ADMIN_C</option>
                    </select>
                  </div>
                  @if (newRole() !== 'ADMIN_A') {
                    <div class="field">
                      <label for="managed-school">Escola</label
                      ><select id="managed-school" name="school" required>
                        <option value="">Selecione a escola</option>
                        @for (s of repo.schools().rows; track s.school_id) {
                          <option [value]="s.school_id">{{ s.name }}</option>
                        }
                      </select>
                    </div>
                    @if (repo.schools().kind === 'error') {
                      <p role="alert">Não foi possível consultar escolas.</p>
                      <button type="button" class="text-button" (click)="repo.load('schools')">
                        Consultar escolas novamente
                      </button>
                    }
                  }
                } @else {
                  <p class="contract-note">
                    ADMIN_C · Escola vinculada ao administrador autenticado
                  </p>
                }
              } @else {
                <p class="contract-note">
                  {{ a.role }} · {{ a.school_name || 'Global' }} · Papel e escola preservados
                </p>
              }
              <div class="field">
                <label for="managed-status">Estado da conta</label
                ><select id="managed-status" name="status">
                  <option value="ACTIVE" [selected]="a?.status !== 'INACTIVE'">Ativo</option>
                  <option
                    value="INACTIVE"
                    [selected]="a?.status === 'INACTIVE'"
                    [disabled]="a?.admin_id === repo.auth.admin()?.id"
                  >
                    Inativo
                  </option>
                </select>
              </div>
            </div>
            @if (!a) {
              <p class="dialog-note">
                Esta operação cria somente a identidade administrativa, sem usuário Auth, convite ou
                senha. A conta não poderá entrar até receber um vínculo de acesso.
              </p>
            }
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
                Cancelar</button
              ><button class="primary-button" type="submit" [disabled]="repo.submitting()">
                {{
                  repo.submitting()
                    ? 'Salvando…'
                    : a
                      ? 'Salvar alterações'
                      : 'Cadastrar administrador'
                }}
              </button>
            </div>
          </form>
        </section>
      </div>
    }`,
})
export class AdministratorsComponent {
  readonly repo = inject(AdminStructureRepository);
  readonly role = input.required<AdminRole>();
  readonly newRole = signal<AdminRole>('ADMIN_A');
  constructor() {
    void this.repo.load('admins');
    if (this.repo.auth.admin()?.role === 'ADMIN_A') void this.repo.load('schools');
  }
  editing() {
    return ['admin-create', 'admin-edit'].includes(this.repo.operation()?.kind || '');
  }
  selected() {
    const op = this.repo.operation();
    return op?.kind === 'admin-edit'
      ? this.repo.admins().rows.find((a) => a.admin_id === op.id)
      : null;
  }
  create() {
    this.newRole.set('ADMIN_A');
    this.repo.open('admin-create');
  }
  save(e: Event) {
    e.preventDefault();
    const data = new FormData(e.currentTarget as HTMLFormElement);
    void this.repo.save({
      p_name: String(data.get('name')),
      p_email: String(data.get('email')),
      p_status: String(data.get('status')),
      ...(this.selected()
        ? {}
        : {
            p_role: this.role() === 'ADMIN_B' ? 'ADMIN_C' : this.newRole(),
            p_school_id:
              this.role() === 'ADMIN_B' || this.newRole() === 'ADMIN_A' ? null : data.get('school'),
          }),
    });
  }
}
