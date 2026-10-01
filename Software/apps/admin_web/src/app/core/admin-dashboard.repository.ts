import { computed, inject, Injectable } from '@angular/core';
import { AdminAuthService } from './admin-auth.service';
import { AdminStructureRepository } from './admin-structure.repository';
import { AdminSchoolRepository } from './admin-school.repository';
import { ClassChangeRequestsRepository } from './class-change-requests.repository';
import { AdminBinbazarRepository } from './admin-binbazar.repository';
import { BinbazarPriceCapRepository } from './binbazar-price-cap.repository';

type Kind = 'loading' | 'loaded' | 'error';
@Injectable()
export class AdminDashboardRepository {
  readonly auth = inject(AdminAuthService);
  readonly structure = inject(AdminStructureRepository);
  readonly school = inject(AdminSchoolRepository);
  readonly requests = inject(ClassChangeRequestsRepository);
  readonly binbazar = inject(AdminBinbazarRepository);
  readonly cap = inject(BinbazarPriceCapRepository);
  // Composição das fontes existentes, sem cache ou autorização paralelos.
  readonly pendingRequests = computed(() =>
    this.requests
      .state()
      .rows.filter((r) => r.status === 'PENDING')
      .sort(
        (a, b) =>
          b.created_at.localeCompare(a.created_at) || a.request_id.localeCompare(b.request_id),
      ),
  );
  readonly pendingRedemptions = computed(() =>
    this.binbazar
      .redemptions()
      .rows.filter((r) => r.status === 'PENDING')
      .sort(
        (a, b) =>
          b.created_at.localeCompare(a.created_at) ||
          a.redemption_id.localeCompare(b.redemption_id),
      ),
  );
  readonly outOfStock = computed(() =>
    this.binbazar.products().rows.filter((p) => p.is_active && p.stock_qty === 0),
  );
  readonly kinds = computed(() => [
    this.cap.state().kind,
    ...(this.auth.admin()?.role === 'ADMIN_A'
      ? [this.structure.schools().kind, this.structure.admins().kind]
      : [
          this.school.state().kind,
          this.requests.state().kind,
          this.binbazar.products().kind,
          this.binbazar.redemptions().kind,
          ...(this.auth.admin()?.role === 'ADMIN_B' ? [this.structure.admins().kind] : []),
        ]),
  ]);
  readonly loading = computed(() => this.kinds().includes('loading'));
  readonly failed = computed(() => this.kinds().includes('error'));
  readonly cards = computed(() => {
    const cap = {
      label: 'Teto do BinBazar',
      value:
        this.cap.state().kind === 'loaded'
          ? this.cap.state().value === null
            ? 'Não configurado'
            : this.cap.state().value!.toLocaleString('pt-BR')
          : this.value(this.cap.state().kind, 0),
      note: 'Limite global em BinCoins',
      icon: 'sliders-horizontal',
    };
    const admins = this.structure.admins();
    const activeAdmins = admins.rows.filter((a) => a.status === 'ACTIVE').length;
    if (this.auth.admin()?.role === 'ADMIN_A') {
      const schools = this.structure.schools();
      return [
        {
          label: 'Escolas cadastradas',
          value: this.value(schools.kind, schools.rows.length),
          note: 'Estrutura global',
          icon: 'school',
        },
        {
          label: 'Alunos cadastrados',
          value: this.value(
            schools.kind,
            schools.rows.reduce((n, s) => n + Number(s.student_count), 0),
          ),
          note: 'Soma de todas as escolas',
          icon: 'users',
        },
        {
          label: 'Administradores',
          value: this.value(admins.kind, admins.rows.length),
          note:
            admins.kind === 'loaded'
              ? `${activeAdmins} ACTIVE · ${admins.rows.length - activeAdmins} INACTIVE`
              : 'Contas globais e escolares',
          icon: 'shield-user',
        },
        {
          label: 'Sem vínculo de acesso',
          value: this.value(admins.kind, admins.rows.filter((a) => !a.access_linked).length),
          note: 'Identidades sem vínculo Auth',
          icon: 'user-round',
        },
        {
          label: 'Máquinas cadastradas',
          value: this.value(
            schools.kind,
            schools.rows.reduce((n, s) => n + Number(s.machine_count), 0),
          ),
          note: 'Contagem estrutural; não indica disponibilidade',
          icon: 'monitor',
        },
        cap,
      ];
    }
    const school = this.school.state();
    const activeStudents = school.students.filter((s) => s.status === 'ACTIVE').length;
    return [
      {
        label: 'Alunos ACTIVE',
        value: this.value(school.kind, activeStudents),
        note:
          school.kind === 'loaded'
            ? `${school.students.length - activeStudents} INACTIVE`
            : 'Alunos da escola vinculada',
        icon: 'users',
      },
      {
        label: 'Turmas disponíveis',
        value: this.value(school.kind, school.classes.length),
        note: 'Estrutura atual da escola',
        icon: 'users-round',
      },
      ...(this.auth.admin()?.role === 'ADMIN_B'
        ? [
            {
              label: 'Administradores C',
              value: this.value(admins.kind, admins.rows.length),
              note:
                admins.kind === 'loaded'
                  ? `${activeAdmins} ACTIVE · ${admins.rows.length - activeAdmins} INACTIVE`
                  : 'Contas C da própria escola',
              icon: 'shield-user',
            },
          ]
        : []),
      {
        label:
          this.auth.admin()?.role === 'ADMIN_C' ? 'Minhas solicitações PENDING' : 'Trocas PENDING',
        value: this.value(this.requests.state().kind, this.pendingRequests().length),
        note: 'Aguardam decisão administrativa',
        icon: 'send',
      },
      {
        label: 'Resgates PENDING',
        value: this.value(this.binbazar.redemptions().kind, this.pendingRedemptions().length),
        note: 'Aguardam entrega na escola',
        icon: 'ticket-check',
      },
      {
        label: 'Produtos ativos',
        value: this.value(
          this.binbazar.products().kind,
          this.binbazar.products().rows.filter((p) => p.is_active).length,
        ),
        note:
          this.binbazar.products().kind === 'loaded'
            ? `${this.outOfStock().length} ativos sem estoque`
            : 'Catálogo da própria escola',
        icon: 'package-open',
      },
      cap,
    ];
  });
  value(kind: Kind, count: number) {
    return kind === 'loaded'
      ? count.toLocaleString('pt-BR')
      : kind === 'loading'
        ? '…'
        : 'Indisponível';
  }
  async load() {
    if (!this.auth.admin()) return;
    await Promise.all([
      this.cap.load(),
      ...(this.auth.admin()?.role === 'ADMIN_A'
        ? [this.structure.load('schools'), this.structure.load('admins')]
        : // requests.load já recarrega alunos/turmas; não duplicar essas consultas.
          [
            this.requests.load(),
            this.binbazar.load('products'),
            this.binbazar.load('redemptions'),
            ...(this.auth.admin()?.role === 'ADMIN_B' ? [this.structure.load('admins')] : []),
          ]),
    ]);
  }
}
