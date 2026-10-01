import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminBinbazarRepository } from '../core/admin-binbazar.repository';
import { EntityRowComponent } from '../shared/entity-row.component';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-products',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button class="primary-button compact-button" disabled type="button">
        Cadastrar produto
      </button>
    </div>
    <p class="contract-note">
      Criação e alteração de preço aguardam o teto global persistido do BinGo.
    </p>
    @if (repo.notice()) {
      <p role="status">{{ repo.notice() }}</p>
    }
    @if (repo.products().kind === 'loading') {
      <app-state-panel title="Carregando produtos" body="Consultando a escola vinculada." />
    } @else if (repo.products().kind === 'error') {
      <app-state-panel
        title="Não foi possível carregar produtos"
        body="Confira a conexão e tente novamente."
        [retry]="true"
        (retryClick)="repo.load('products')"
      />
    } @else {
      <section class="panel entity-list">
        @for (p of repo.products().rows; track p.reward_id) {
          <app-entity-row
            icon="package-open"
            [title]="p.name"
            [subtitle]="p.stock_qty === null ? 'Ilimitado' : p.stock_qty + ' unidades'"
            [meta]="p.cost_points + ' BinCoins'"
            [status]="p.is_active ? 'Ativo' : 'Inativo'"
            actionLabel="Editar"
            actionIcon="square-pen"
            (action)="repo.open('product', p.reward_id)"
          />
        } @empty {
          <app-state-panel
            title="Nenhum produto"
            body="Não há produtos cadastrados nesta escola."
          />
        }
      </section>
    }
    @if (selected(); as p) {
      <div class="dialog-backdrop">
        <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true">
          <h2>Editar produto e estoque</h2>
          <form (submit)="save($event)">
            <div class="operation-fields">
              <div class="field">
                <label for="product-name">Produto</label
                ><input id="product-name" name="name" [value]="p.name" required />
              </div>
              <div class="field">
                <label for="product-description">Descrição</label
                ><input id="product-description" name="description" [value]="p.description || ''" />
              </div>
              <div class="field">
                <label for="product-stock">Estoque</label
                ><input
                  id="product-stock"
                  name="stock"
                  type="number"
                  min="0"
                  step="1"
                  [value]="p.stock_qty ?? ''"
                /><small>Deixe vazio para estoque ilimitado.</small>
              </div>
              <div class="field">
                <label for="product-active">Disponibilidade</label
                ><select id="product-active" name="active">
                  <option value="true" [selected]="p.is_active">Ativo</option>
                  <option value="false" [selected]="!p.is_active">Inativo</option>
                </select>
              </div>
              <p>Preço: {{ p.cost_points }} BinCoins. Alteração aguardando teto global.</p>
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
                {{ repo.submitting() ? 'Salvando…' : 'Salvar alterações' }}
              </button>
            </div>
          </form>
        </section>
      </div>
    }`,
})
export class ProductsComponent {
  readonly repo = inject(AdminBinbazarRepository);
  constructor() {
    void this.repo.load('products');
  }
  selected() {
    const op = this.repo.operation();
    return op?.action === 'product'
      ? this.repo.products().rows.find((p) => p.reward_id === op.id)
      : null;
  }
  save(e: Event) {
    e.preventDefault();
    const data = new FormData(e.currentTarget as HTMLFormElement);
    const stock = String(data.get('stock')).trim();
    void this.repo.mutate({
      p_name: String(data.get('name')),
      p_description: String(data.get('description')) || null,
      p_stock_qty: stock === '' ? null : Number(stock),
      p_is_active: data.get('active') === 'true',
    });
  }
}
