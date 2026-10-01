import { AdminBinbazarRepository } from '../core/admin-binbazar.repository';
import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  inject,
  input,
  output,
} from '@angular/core';
import { AdminView, ADMIN_ROLES, canAccessView, firstViewForRole } from '../admin-access';
import { AdminStore } from '../core/admin-store';
import { AdminContext } from '../core/admin-context';
import { AdminAComponent, AdminBComponent, AdminCComponent } from '../roles/admin-role-components';
import { AdminSchoolDialogComponent } from '../features/admin-school-dialog.component';
import { OperationDialogComponent } from '../shared/operation-dialog.component';
import { StatePanelComponent } from '../shared/state-panel.component';
const meta: Record<AdminView, { label: string; icon: string; title: string; subtitle: string }> = {
  overview: {
    label: 'Visão geral',
    icon: 'layout-dashboard',
    title: 'Operação da escola',
    subtitle: 'Solicitações próprias, resgates, alunos e estoque da escola vinculada.',
  },
  schools: {
    label: 'Escolas',
    icon: 'school',
    title: 'Escolas participantes',
    subtitle: 'Estrutura global das escolas vinculadas ao ecossistema BinGo.',
  },
  administrators: {
    label: 'Administradores',
    icon: 'shield-user',
    title: 'Contas administrativas',
    subtitle: 'Acessos ativos e inativos dentro do escopo permitido.',
  },
  students: {
    label: 'Alunos',
    icon: 'users',
    title: 'Alunos da escola',
    subtitle: 'Consulta e administração dos alunos da escola vinculada.',
  },
  classes: {
    label: 'Turmas',
    icon: 'users-round',
    title: 'Turmas da escola',
    subtitle: 'Segmento, série e XP atual das turmas da escola.',
  },
  pending: {
    label: 'Pendências',
    icon: 'list-todo',
    title: 'Pendências da escola',
    subtitle: 'Decisões administrativas e operações que precisam de atenção.',
  },
  requests: {
    label: 'Solicitações',
    icon: 'send',
    title: 'Minhas solicitações',
    subtitle: 'Pedidos operacionais enviados para avaliação dos administradores da escola.',
  },
  deposits: {
    label: 'Descartes',
    icon: 'archive-restore',
    title: 'Descartes recentes',
    subtitle: 'Itens validados pelos Totens e sua situação operacional.',
  },
  help: {
    label: 'Solicitações de ajuda',
    icon: 'circle-help',
    title: 'Solicitações de ajuda',
    subtitle: 'Fila de apoio enviada pelos Totens para acompanhamento da equipe.',
  },
  products: {
    label: 'Produtos e estoque',
    icon: 'package-open',
    title: 'Produtos do BinBazar',
    subtitle: 'Catálogo, preço, disponibilidade e estoque administrados pela escola.',
  },
  redemptions: {
    label: 'Resgates',
    icon: 'ticket-check',
    title: 'Resgates pendentes',
    subtitle: 'Confirme a entrega das recompensas solicitadas pelos alunos.',
  },
  missions: {
    label: 'Missões',
    icon: 'flag',
    title: 'Missões do BinGo',
    subtitle: 'Ciclos globais disponíveis e sua situação nas escolas.',
  },
  machines: {
    label: 'Totens',
    icon: 'monitor-cog',
    title: 'Estado dos Totens',
    subtitle: 'Estado e sinais persistidos dos equipamentos, sem diagnóstico em tempo real.',
  },
  economy: {
    label: 'Economia',
    icon: 'sliders-horizontal',
    title: 'Configurações econômicas',
    subtitle: 'Valores-base, bônus ambientais, metas e teto global do BinBazar.',
  },
};
@Component({
  selector: 'app-admin-shell',
  imports: [
    AdminAComponent,
    AdminBComponent,
    AdminCComponent,
    OperationDialogComponent,
    AdminSchoolDialogComponent,
    StatePanelComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="admin-shell">
    <aside class="sidebar">
      <div class="sidebar-brand">
        <img src="assets/brand/logo-bingo.png" alt="BinGo" /><span>Admin Lite</span>
      </div>
      <nav class="side-nav">
        @for (v of definition().views; track v) {
          <button
            class="nav-button"
            type="button"
            [attr.aria-current]="store.view() === v ? 'page' : 'false'"
            (click)="select(v)"
          >
            <span class="nav-glyph"><i [attr.data-lucide]="meta[v].icon"></i></span
            ><span>{{ meta[v].label }}</span>
            @if (count(v)) {
              <span class="nav-count">{{ count(v) }}</span>
            }
          </button>
        }
      </nav>
      <div class="sidebar-footer">
        <div class="operator">
          <span class="operator-avatar">{{ initials() }}</span
          ><span
            ><strong>{{ admin().name }}</strong
            ><small>{{ definition().shortLabel }}</small></span
          >
        </div>
        <button class="text-button" type="button" (click)="logout.emit()">
          <i data-lucide="log-out"></i><span>Sair</span>
        </button>
      </div>
    </aside>
    <div class="main-area">
      <header class="topbar">
        <div class="topbar-copy">
          <strong>{{ scope() }}</strong
          ><span>{{
            realSchoolView()
              ? 'Fotografia de dados reais'
              : 'Última atualização demonstrativa: agora'
          }}</span>
        </div>
        <div class="topbar-actions">
          <span class="status-pill"
            ><i data-lucide="circle-check"></i
            >{{
              ['overview', 'machines'].includes(store.view())
                ? 'Somente leitura'
                : 'Sistema operacional'
            }}</span
          >
          @if (!realSchoolView()) {
            <label
              ><span class="sr-only">Cenário da demonstração</span
              ><select
                class="demo-select"
                aria-label="Cenário da demonstração"
                [value]="store.scenario()"
                (change)="scenario($event)"
              >
                <option value="normal">Dados normais</option>
                <option value="loading">Carregando</option>
                <option value="empty">Sem dados</option>
                <option value="error">Falha de conexão</option>
              </select></label
            >
          }
        </div>
      </header>
      <main class="page-content" tabindex="-1">
        <div class="page-heading">
          <div>
            <p class="eyebrow">{{ definition().shortLabel }}</p>
            <h1>{{ heading().title }}</h1>
            <p>{{ heading().subtitle }}</p>
          </div>
          <span class="source-pill"
            ><i data-lucide="database"></i
            >{{
              store.view() === 'economy'
                ? 'Teto real · Outras regras demonstrativas'
                : store.view() === 'pending'
                  ? 'Trocas e resgates reais'
                  : realSchoolView()
                    ? this.role() === 'ADMIN_A'
                      ? 'Dados reais do ecossistema'
                      : 'Dados da escola vinculada'
                    : 'Dados demonstrativos'
            }}</span
          >
        </div>
        @switch (realSchoolView() ? 'normal' : store.scenario()) {
          @case ('loading') {
            <section class="state-panel">
              <div class="skeleton-stack">
                <div class="skeleton"></div>
                <div class="skeleton"></div>
                <div class="skeleton"></div>
              </div>
            </section>
          }
          @case ('empty') {
            <app-state-panel
              title="Nada por aqui agora"
              body="Quando novos registros chegarem, eles aparecerão nesta área."
            />
          }
          @case ('error') {
            <app-state-panel
              icon="circle-alert"
              title="Não foi possível atualizar"
              body="Confira a conexão e tente novamente. Nenhuma ação foi realizada."
              [retry]="true"
              (retryClick)="retry()"
            />
          }
          @default {
            @switch (role()) {
              @case ('ADMIN_A') {
                <app-admin-a [view]="store.view()" />
              }
              @case ('ADMIN_B') {
                <app-admin-b [view]="store.view()" />
              }
              @default {
                <app-admin-c [view]="store.view()" />
              }
            }
          }
        }
      </main>
    </div>
    <app-operation-dialog />
    <app-admin-school-dialog />
    @if (store.toast()) {
      <div class="toast" role="status">{{ store.toast() }}</div>
    }
  </div>`,
})
export class AdminShellComponent {
  readonly admin = input.required<AdminContext>();
  readonly role = computed(() => this.admin().role);
  readonly logout = output<void>();
  readonly store = inject(AdminStore);
  readonly binbazar = inject(AdminBinbazarRepository);
  readonly meta = meta;
  constructor() {
    effect(() => {
      this.store.view.set(firstViewForRole(this.role()));
      this.store.scenario.set('normal');
    });
  }
  realSchoolView() {
    return [
      'overview',
      'schools',
      'administrators',
      'machines',
      'students',
      'classes',
      'requests',
      'pending',
      'products',
      'redemptions',
      'economy',
    ].includes(this.store.view());
  }
  definition() {
    return ADMIN_ROLES[this.role()];
  }
  initials() {
    return this.admin()
      .name.trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0])
      .join('')
      .toUpperCase();
  }
  scope() {
    return this.role() === 'ADMIN_A' ? 'Ecossistema BinGo · Global' : 'Escopo da escola vinculada';
  }
  heading() {
    if (this.store.view() !== 'overview') return meta[this.store.view()];
    return this.role() === 'ADMIN_A'
      ? {
          title: 'Visão global do BinGo',
          subtitle: 'Escolas, contas administrativas e teto global consultados no backend.',
        }
      : this.role() === 'ADMIN_B'
        ? {
            title: 'Gestão da escola',
            subtitle: 'Pessoas, pendências e recursos que precisam da administração da escola.',
          }
        : {
            title: 'Operação da escola',
            subtitle: 'Solicitações próprias, resgates, alunos e estoque da escola vinculada.',
          };
  }
  count(v: AdminView) {
    return v === 'help' && this.store.view() !== 'overview'
      ? this.store.openHelp()
      : v === 'redemptions' || v === 'pending'
        ? this.binbazar.redemptions().rows.filter((r) => r.status === 'PENDING').length
        : 0;
  }
  select(v: AdminView) {
    if (canAccessView(this.role(), v)) {
      this.store.view.set(v);
      this.store.scenario.set('normal');
    }
  }
  scenario(e: Event) {
    this.store.scenario.set((e.target as HTMLSelectElement).value as any);
  }
  retry() {
    this.store.scenario.set('normal');
    this.store.notify('Dados demonstrativos carregados novamente.');
  }
}
