import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
@Component({
  selector: 'app-state-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="state-panel">
    <div class="state-content">
      <span class="state-icon"><i [attr.data-lucide]="icon()"></i></span>
      <h2>{{ title() }}</h2>
      <p>{{ body() }}</p>
      @if (retry()) {
        <button
          class="secondary-button"
          type="button"
          style="margin-top:18px"
          (click)="retryClick.emit()"
        >
          <i data-lucide="rotate-cw"></i><span>Tentar novamente</span>
        </button>
      }
    </div>
  </section>`,
})
export class StatePanelComponent {
  icon = input('inbox');
  title = input.required<string>();
  body = input.required<string>();
  retry = input(false);
  retryClick = output<void>();
}
