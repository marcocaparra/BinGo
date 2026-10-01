import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminSchoolRepository } from '../core/admin-school.repository';

@Component({
  selector: 'app-admin-school-dialog',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@if (school.operation(); as op) {
    <div class="dialog-backdrop" (click)="backdrop($event)">
      <section
        class="confirm-dialog operation-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="school-dialog-title"
      >
        <span class="confirm-dialog-icon"><i data-lucide="users-round"></i></span>
        <p class="eyebrow">Dados da escola vinculada</p>
        <h2 id="school-dialog-title">{{ title() }}</h2>
        <form (submit)="submit($event)">
          <div class="operation-fields">
            @if (op.action.startsWith('student-')) {
              @let s = student();
              <div class="field">
                <label for="school-name">Nome completo</label>
                <input
                  id="school-name"
                  name="name"
                  [value]="s?.name || ''"
                  [readOnly]="viewOnly()"
                  required
                />
              </div>
              <div class="field">
                <label for="school-email">E-mail institucional</label>
                <input
                  id="school-email"
                  name="email"
                  type="email"
                  [value]="s?.email || ''"
                  [readOnly]="viewOnly()"
                />
              </div>
              <div class="field">
                <label for="school-registration">RA ou matrícula</label>
                <input
                  id="school-registration"
                  name="registration"
                  type="text"
                  [value]="s?.registration || ''"
                  [readOnly]="viewOnly()"
                  [required]="!viewOnly()"
                />
              </div>
              <div class="field">
                <label for="school-class">Turma</label>
                @if (viewOnly()) {
                  <input id="school-class" [value]="s?.class_name || ''" readonly />
                } @else {
                  <select id="school-class" name="class_id" required>
                    <option value="">Selecione uma turma</option>
                    @for (c of school.state().classes; track c.class_id) {
                      <option [value]="c.class_id" [selected]="c.class_id === s?.class_id">
                        {{ c.name }}
                      </option>
                    }
                  </select>
                }
              </div>
              <div class="field">
                <label for="school-status">Estado</label>
                <select id="school-status" name="status" [disabled]="viewOnly()">
                  <option value="ACTIVE" [selected]="s?.status !== 'INACTIVE'">Ativo</option>
                  <option value="INACTIVE" [selected]="s?.status === 'INACTIVE'">Inativo</option>
                </select>
              </div>
              @if (viewOnly()) {
                <p class="dialog-note">
                  {{ s?.points_student_balance }} BinCoins · {{ s?.class_points_balance }} XP da
                  turma. Consulta somente leitura.
                </p>
              }
            } @else {
              @let c = classItem();
              <div class="field">
                <label for="school-name">Nome da turma</label>
                <input id="school-name" name="name" [value]="c?.name || ''" required />
              </div>
              <div class="field">
                <label for="school-segment">Segmento</label>
                <input id="school-segment" name="segment" [value]="c?.segment || ''" required />
              </div>
              <div class="field">
                <label for="school-grade">Série/grade</label>
                <input id="school-grade" name="grade" [value]="c?.grade || ''" required />
              </div>
            }
          </div>
          @if (school.mutationError()) {
            <p class="dialog-note" role="alert">{{ school.mutationError() }}</p>
          }
          <div class="dialog-actions">
            <button
              class="secondary-button"
              type="button"
              [disabled]="school.saving()"
              (click)="school.close()"
            >
              {{ viewOnly() ? 'Fechar' : 'Cancelar' }}
            </button>
            @if (!viewOnly()) {
              <button class="primary-button" type="submit" [disabled]="school.saving()">
                <i data-lucide="check"></i
                ><span>{{ school.saving() ? 'Salvando…' : submitLabel() }}</span>
              </button>
            }
          </div>
        </form>
      </section>
    </div>
  }`,
})
export class AdminSchoolDialogComponent {
  readonly school = inject(AdminSchoolRepository);
  student() {
    return this.school.state().students.find((s) => s.student_id === this.school.operation()?.id);
  }
  classItem() {
    return this.school.state().classes.find((c) => c.class_id === this.school.operation()?.id);
  }
  viewOnly() {
    return this.school.operation()?.action === 'student-view';
  }
  title() {
    return {
      'student-create': 'Cadastrar aluno',
      'student-edit': 'Editar dados do aluno',
      'student-view': 'Consultar aluno',
      'class-create': 'Criar turma',
      'class-edit': 'Editar turma',
    }[this.school.operation()!.action];
  }
  submitLabel() {
    return this.school.operation()?.action.endsWith('-create') ? this.title() : 'Salvar alterações';
  }
  backdrop(e: MouseEvent) {
    if (e.target === e.currentTarget) this.school.close();
  }
  submit(e: Event) {
    e.preventDefault();
    void this.school.submit(e.currentTarget as HTMLFormElement);
  }
}
