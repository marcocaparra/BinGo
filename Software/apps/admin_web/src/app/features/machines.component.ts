import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminStore } from '../core/admin-store';
@Component({
  selector: 'app-machines',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<section class="machine-grid">
    @for (m of store.machines; track m.code) {
      <article
        class="machine-card"
        [style.--status-color]="m.color"
        [style.--status-ink]="m.ink"
        [style.--status-bg]="m.bg"
      >
        <div class="machine-card-head">
          <div>
            <h2>{{ m.name }}</h2>
            <p>{{ m.code }}</p>
          </div>
          <span class="health-pill"
            ><i
              [attr.data-lucide]="
                m.status === 'Online'
                  ? 'circle-check'
                  : m.status === 'Com problema'
                    ? 'triangle-alert'
                    : 'wifi-off'
              "
            ></i
            >{{ m.status }}</span
          >
        </div>
        <div class="machine-metrics">
          <div class="machine-metric">
            <small>Câmera</small><strong>{{ m.camera }}</strong>
          </div>
          <div class="machine-metric">
            <small>Porta</small><strong>{{ m.door }}</strong>
          </div>
          <div class="machine-metric">
            <small>Depósitos</small><strong>{{ m.deposits }}</strong>
          </div>
          <div class="machine-metric">
            <small>Versão</small><strong>{{ m.version }}</strong>
          </div>
        </div>
        <footer class="machine-footer">
          <span class="last-seen"
            ><i data-lucide="radio"></i
            ><span
              >Última comunicação<br /><strong>{{ m.lastSeen }}</strong></span
            ></span
          ><button
            class="text-button"
            type="button"
            (click)="store.open('machine-view', null, m.code)"
          >
            <span>Ver diagnóstico</span><i data-lucide="arrow-up-right"></i>
          </button>
        </footer>
      </article>
    }
  </section>`,
})
export class MachinesComponent {
  readonly store = inject(AdminStore);
}
