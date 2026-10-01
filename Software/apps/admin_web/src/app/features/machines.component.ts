import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminMachinesRepository } from '../core/admin-machines.repository';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-machines',
  imports: [DatePipe, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="secondary-button"
        type="button"
        [disabled]="repo.state().kind === 'loading'"
        (click)="repo.load()"
      >
        Atualizar Totens
      </button>
    </div>
    <p>Fotografia persistida. Os campos não comprovam disponibilidade operacional atual.</p>
    @if (repo.state().kind === 'loading') {
      <app-state-panel
        title="Carregando Totens"
        body="Consultando os registros disponíveis para sua conta."
      />
    } @else if (repo.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar Totens"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load()"
      />
    } @else {
      <section class="machine-grid">
        @for (m of repo.state().rows; track m.machine_id) {
          <article
            class="machine-card"
            style="--status-color:#777;--status-ink:#444;--status-bg:#f2f2f2"
          >
            <div class="machine-card-head">
              <div>
                <h2>{{ m.name }}</h2>
                <p>{{ m.school_name }}</p>
              </div>
              <span class="health-pill">{{ m.status }}</span>
            </div>
            <div class="machine-metrics">
              <div class="machine-metric">
                <small>Câmera</small
                ><strong>{{ m.camera_ok ? 'OK registrado' : 'Falha registrada' }}</strong>
              </div>
              <div class="machine-metric">
                <small>Rede</small
                ><strong>{{ m.net_ok ? 'OK registrado' : 'Falha registrada' }}</strong>
              </div>
              <div class="machine-metric">
                <small>Compartimento</small
                ><strong>{{ m.bin_full ? 'Cheio' : 'Disponível' }}</strong>
              </div>
              <div class="machine-metric">
                <small>Firmware</small><strong>{{ m.firmware_version ?? 'Não informado' }}</strong>
              </div>
            </div>
            <footer class="machine-footer">
              <span class="last-seen"
                ><span
                  >Última comunicação<br /><strong>{{
                    m.last_seen === null
                      ? 'Não registrada'
                      : (m.last_seen | date: 'dd/MM/yyyy HH:mm:ss')
                  }}</strong></span
                ></span
              >
            </footer>
          </article>
        } @empty {
          <app-state-panel title="Nenhum Totem" body="Não há Totens cadastrados no seu escopo." />
        }
      </section>
    }`,
})
export class MachinesComponent {
  readonly repo = inject(AdminMachinesRepository);
  constructor() {
    void this.repo.load();
  }
}
