import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { BinbazarPriceCapRepository } from '../core/binbazar-price-cap.repository';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-binbazar-price-cap',
  imports: [StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<p class="contract-note">Configuração global real · BinBazar</p>
    @if (cap.notice()) {
      <p role="status">{{ cap.notice() }}</p>
    }
    @if (cap.state().kind === 'loading') {
      <app-state-panel title="Carregando teto global" body="Consultando configuração do BinGo." />
    } @else if (cap.state().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar o teto"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="cap.load()"
      />
    } @else {
      <section class="settings-grid">
        <article class="setting-card">
          <span class="activity-icon"><i data-lucide="badge-dollar-sign"></i></span>
          <div>
            <small>Teto do BinBazar</small
            ><strong>{{
              cap.state().value === null ? 'Ainda não configurado' : cap.state().value + ' BinCoins'
            }}</strong>
            <p>
              Limite global para novos produtos e alterações de preço. A redução não modifica
              produtos existentes.
            </p>
          </div>
          <button class="row-action" type="button" (click)="cap.open()">
            {{ cap.state().value === null ? 'Definir teto' : 'Editar teto' }}
          </button>
        </article>
      </section>
    }
    @if (cap.editing()) {
      <div class="dialog-backdrop">
        <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true">
          <h2>Definir teto global do BinBazar</h2>
          <form (submit)="save($event)">
            <div class="operation-fields">
              <div class="field">
                <label for="price-cap">Teto máximo em BinCoins</label
                ><input
                  id="price-cap"
                  name="cap"
                  type="number"
                  min="1"
                  step="1"
                  [value]="cap.state().value ?? ''"
                  required
                />
              </div>
            </div>
            @if (cap.error()) {
              <p role="alert">{{ cap.error() }}</p>
            }
            <div class="dialog-actions">
              <button
                class="secondary-button"
                type="button"
                [disabled]="cap.saving()"
                (click)="cap.close()"
              >
                Cancelar</button
              ><button class="primary-button" type="submit" [disabled]="cap.saving()">
                {{ cap.saving() ? 'Salvando…' : 'Salvar teto' }}
              </button>
            </div>
          </form>
        </section>
      </div>
    }`,
})
export class BinbazarPriceCapComponent {
  readonly cap = inject(BinbazarPriceCapRepository);
  constructor() {
    void this.cap.load();
  }
  save(e: Event) {
    e.preventDefault();
    void this.cap.save(Number(new FormData(e.currentTarget as HTMLFormElement).get('cap')));
  }
}
