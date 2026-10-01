import { ChangeDetectionStrategy, Component, inject, input, signal } from '@angular/core';
import { ClassChangeRequestsRepository } from '../core/class-change-requests.repository';
import { EntityRowComponent } from '../shared/entity-row.component';
import { StatePanelComponent } from '../shared/state-panel.component';

@Component({
  selector: 'app-class-requests',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (requests.state().kind === 'loading') {
      <app-state-panel
        title="Carregando solicitações…"
        body="Consultando solicitações da escola."
      />
    } @else if (requests.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar solicitações"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="requests.load()"
      />
    } @else {
      @if (!manage()) {
        <div class="toolbar toolbar--end">
          <button
            class="primary-button compact-button"
            type="button"
            [disabled]="requests.school.state().kind !== 'loaded' || requests.submitting()"
            (click)="openCreate()"
          >
            <i data-lucide="plus"></i><span>Solicitar troca de turma</span>
          </button>
        </div>
        @if (requests.school.state().kind === 'error') {
          <app-state-panel
            title="Não foi possível carregar alunos e turmas"
            body="A seleção precisa de dados reais."
            [retry]="true"
            (retryClick)="requests.load()"
          />
        }
      }
      @if (!requests.state().rows.length) {
        <app-state-panel
          title="Nenhuma solicitação registrada"
          body="Novas solicitações e seu histórico aparecerão aqui."
        />
      } @else {
        <div class="entity-list">
          @for (r of requests.state().rows; track r.request_id) {
            <app-entity-row
              icon="users-round"
              [title]="r.student_name + ' · ' + (r.registration || 'Matrícula não informada')"
              [subtitle]="r.source_class_name + ' → ' + r.destination_class_name"
              [meta]="
                'Turma atual: ' +
                r.current_class_name +
                ' · Solicitado por ' +
                r.requested_by_admin_name
              "
              [status]="statusLabel(r.status)"
              [actionLabel]="r.status === 'PENDING' ? (manage() ? 'Analisar' : 'Cancelar') : ''"
              actionIcon="check-check"
              (action)="requests.open(manage() ? 'review' : 'cancel', r.request_id)"
            />
            @if (r.is_stale) {
              <p class="contract-note" role="status">
                A turma atual mudou. Solicitação obsoleta: aprovação bloqueada.
              </p>
            }
            <p class="contract-note">
              Criada em {{ date(r.created_at) }}
              @if (r.resolved_at) {
                · {{ r.resolved_by_admin_name }} em {{ date(r.resolved_at) }}
              }
            </p>
          }
        </div>
      }
    }
    @if (requests.notice()) {
      <p class="contract-note" role="status">{{ requests.notice() }}</p>
    }
    <p class="contract-note">
      <i data-lucide="history"></i>A turma só muda com aprovação de um Admin B. Solicitações
      concluídas permanecem no histórico.
    </p>
    @if (requests.operation(); as op) {
      <div class="dialog-backdrop" (click)="backdrop($event)">
        <section
          class="confirm-dialog operation-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="request-title"
        >
          <span class="confirm-dialog-icon"><i data-lucide="users-round"></i></span>
          <p class="eyebrow">Solicitação real de troca de turma</p>
          <h2 id="request-title">
            {{
              op.action === 'create'
                ? 'Solicitar troca de turma'
                : op.action === 'review'
                  ? 'Analisar troca de turma'
                  : 'Cancelar solicitação'
            }}
          </h2>
          @if (op.action === 'create') {
            <form (submit)="create($event)">
              <div class="operation-fields">
                <div class="field">
                  <label for="request-student">Aluno</label
                  ><select
                    id="request-student"
                    name="student_id"
                    required
                    [disabled]="requests.submitting()"
                    (change)="studentId.set($any($event.target).value)"
                  >
                    <option value="">Selecione um aluno</option>
                    @for (s of requests.school.state().students; track s.student_id) {
                      <option [value]="s.student_id">
                        {{ s.name }} · {{ s.registration || 'Matrícula não informada' }} ·
                        {{ s.class_name }}
                      </option>
                    }
                  </select>
                </div>
                <div class="field">
                  <label for="request-destination">Nova turma</label
                  ><select
                    id="request-destination"
                    name="destination_class_id"
                    required
                    [disabled]="requests.submitting()"
                  >
                    <option value="">Selecione uma turma</option>
                    @for (c of requests.school.state().classes; track c.class_id) {
                      @if (c.class_id !== currentClassId()) {
                        <option [value]="c.class_id">{{ c.name }}</option>
                      }
                    }
                  </select>
                </div>
              </div>
              @if (requests.error()) {
                <p class="dialog-note" role="alert">{{ requests.error() }}</p>
              }
              <div class="dialog-actions">
                <button
                  class="secondary-button"
                  type="button"
                  [disabled]="requests.submitting()"
                  (click)="requests.close()"
                >
                  Fechar</button
                ><button class="primary-button" type="submit" [disabled]="requests.submitting()">
                  {{ requests.submitting() ? 'Enviando…' : 'Enviar solicitação' }}
                </button>
              </div>
            </form>
          } @else {
            @let r = requests.selected();
            <div class="operation-summary">
              <strong>{{ r?.student_name }}</strong
              ><span>{{ r?.source_class_name }} → {{ r?.destination_class_name }}</span
              ><small>Turma atual: {{ r?.current_class_name }}</small>
            </div>
            @if (r?.is_stale) {
              <p class="dialog-note" role="alert">
                A turma atual mudou. Aprovação bloqueada; a solicitação pode ser rejeitada.
              </p>
            }
            @if (requests.error()) {
              <p class="dialog-note" role="alert">{{ requests.error() }}</p>
            }
            <div class="dialog-actions">
              <button
                class="secondary-button"
                type="button"
                [disabled]="requests.submitting()"
                (click)="requests.close()"
              >
                Fechar
              </button>
              @if (op.action === 'review') {
                <button
                  class="danger-button"
                  type="button"
                  [disabled]="requests.submitting() || r?.status !== 'PENDING'"
                  (click)="requests.decide('reject')"
                >
                  Rejeitar
                </button>
                <button
                  class="primary-button"
                  type="button"
                  [disabled]="requests.submitting() || !r || r.status !== 'PENDING' || r.is_stale"
                  (click)="requests.decide('approve')"
                >
                  {{ requests.submitting() ? 'Registrando…' : 'Aprovar troca' }}
                </button>
              } @else {
                <button
                  class="primary-button"
                  type="button"
                  [disabled]="requests.submitting() || r?.status !== 'PENDING'"
                  (click)="requests.decide('cancel')"
                >
                  {{ requests.submitting() ? 'Registrando…' : 'Confirmar cancelamento' }}
                </button>
              }
            </div>
          }
        </section>
      </div>
    }`,
})
export class ClassRequestsComponent {
  readonly requests = inject(ClassChangeRequestsRepository);
  readonly manage = input(false);
  readonly studentId = signal('');
  constructor() {
    void this.requests.load();
  }
  currentClassId() {
    return this.requests.school.state().students.find((s) => s.student_id === this.studentId())
      ?.class_id;
  }
  openCreate() {
    this.studentId.set('');
    this.requests.open('create');
  }
  statusLabel(status: string) {
    return (
      {
        PENDING: 'Pendente',
        APPROVED: 'Aprovada',
        REJECTED: 'Rejeitada',
        CANCELED: 'Cancelada',
      } as Record<string, string>
    )[status];
  }
  date(value: string) {
    return new Date(value).toLocaleString('pt-BR');
  }
  backdrop(event: MouseEvent) {
    if (event.target === event.currentTarget) this.requests.close();
  }
  create(event: Event) {
    event.preventDefault();
    void this.requests.create(event.currentTarget as HTMLFormElement);
  }
}
