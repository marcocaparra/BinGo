import { ChangeDetectionStrategy, Component, input } from '@angular/core';
@Component({
  selector: 'app-summary-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<article class="summary-card" [style.--accent]="accent()">
    <span class="summary-icon"><i [attr.data-lucide]="icon()"></i></span><small>{{ label() }}</small
    ><strong>{{ value() }}</strong
    ><span>{{ note() }}</span>
  </article>`,
})
export class SummaryCardComponent {
  label = input.required<string>();
  value = input.required<string>();
  note = input.required<string>();
  accent = input.required<string>();
  icon = input.required<string>();
}
