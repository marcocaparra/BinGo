import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { AdminBinbazarRepository } from '../core/admin-binbazar.repository';
import { EntityRowComponent } from '../shared/entity-row.component';
import { StatePanelComponent } from '../shared/state-panel.component';
@Component({
  selector: 'app-products',
  imports: [EntityRowComponent, StatePanelComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="toolbar toolbar--end">
      <button
        class="primary-button compact-button"
        type="button"
        [disabled]="
          repo.cap.state().kind !== 'loaded' || repo.cap.state().value === null || repo.submitting()
        "
        (click)="repo.create()"
      >
        Cadastrar produto
      </button>
    </div>
    <p class="contract-note">
      @if (repo.cap.state().kind === 'loading') {
        Carregando teto global…
      } @else if (repo.cap.state().kind === 'error') {
        Não foi possível consultar o teto. Criação e alteração de preço indisponíveis.
        <button class="text-button" (click)="repo.cap.load()">Consultar teto novamente</button>
      } @else if (repo.cap.state().value === null) {
        ADMIN_A precisa definir o teto global. Criação e alteração de preço indisponíveis; outras
        edições continuam permitidas.
      } @else {
        Teto global vigente: {{ repo.cap.state().value }} BinCoins.
      }
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
          <h2>{{ creating() ? 'Cadastrar produto' : 'Editar produto e estoque' }}</h2>
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
              <div class="field">
                <label for="product-price">Preço em BinCoins</label
                ><input
                  id="product-price"
                  name="price"
                  type="number"
                  min="1"
                  step="1"
                  [value]="p.cost_points || ''"
                  [disabled]="repo.cap.state().kind !== 'loaded' || repo.cap.state().value === null"
                  required
                /><small
                  >O teto se aplica quando o preço muda; preços históricos não são reduzidos
                  automaticamente.</small
                >
              </div>
              <div class="field">
                <label for="product-category">Categoria</label
                ><input id="product-category" name="category" [value]="p.category || ''" />
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
              ><button
                class="primary-button"
                type="submit"
                [disabled]="
                  repo.submitting() ||
                  (creating() &&
                    (repo.cap.state().kind !== 'loaded' || repo.cap.state().value === null))
                "
              >
                {{
                  repo.submitting()
                    ? 'Salvando…'
                    : creating()
                      ? 'Cadastrar produto'
                      : 'Salvar alterações'
                }}
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
    void this.repo.cap.load();
  }
  creating() {
    return this.repo.operation()?.action === 'create-product';
  }
  selected() {
    const op = this.repo.operation();
    if (this.creating())
      return {
        reward_id: op!.id,
        name: '',
        description: null,
        category: null,
        cost_points: 0,
        is_active: true,
        stock_qty: null,
      };
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
      p_cost_points: data.has('price') ? Number(data.get('price')) : this.selected()!.cost_points,
      p_category: String(data.get('category')) || null,
      p_is_active: data.get('active') === 'true',
    });
  }
}
