import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
@Component({
  selector: 'app-entity-row',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<article class="entity-row">
    <span class="activity-icon"><i [attr.data-lucide]="icon()"></i></span>
    <div class="row-copy">
      <strong>{{ title() }}</strong
      ><span>{{ subtitle() }}</span>
    </div>
    <div class="row-meta">
      <strong>{{ meta() }}</strong>
    </div>
    @if (status()) {
      <span
        class="tag"
        [class.tag--success]="good()"
        [class.tag--warning]="warn()"
        [class.tag--danger]="!good() && !warn()"
        >{{ status() }}</span
      >
    }
    @if (actionLabel()) {
      <button
        class="row-action"
        [class.row-action--primary]="primary()"
        type="button"
        (click)="action.emit()"
      >
        <i [attr.data-lucide]="actionIcon()"></i><span>{{ actionLabel() }}</span>
      </button>
    }
  </article>`,
})
export class EntityRowComponent {
  icon = input.required<string>();
  title = input.required<string>();
  subtitle = input.required<string>();
  meta = input.required<string>();
  status = input('');
  actionLabel = input('');
  actionIcon = input('arrow-up-right');
  primary = input(false);
  action = output<void>();
  good = () => ['Ativa', 'Ativo', 'Online', 'Aprovada'].includes(this.status());
  warn = () => ['Pendente', 'Implantação'].includes(this.status());
}
