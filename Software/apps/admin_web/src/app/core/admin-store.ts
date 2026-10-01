import { computed, effect, inject, Injectable, signal } from '@angular/core';
import { AdminView } from '../admin-access';
import { AdminAuthService } from './admin-auth.service';

export interface Operation {
  action: string;
  index: number | null;
  key: string | null;
}
@Injectable({ providedIn: 'root' })
export class AdminStore {
  // Somente para composicao das telas demo; nao e autoridade de sessao.
  private readonly auth = inject(AdminAuthService);
  readonly role = computed(() => this.auth.admin()?.role ?? null);
  readonly view = signal<AdminView>('overview');
  readonly scenario = signal<'normal' | 'loading' | 'empty' | 'error'>('normal');
  readonly toast = signal('');
  readonly activeOperation = signal<Operation | null>(null);
  readonly redemptionToDeliver = signal<string | null>(null);
  readonly helpFilter = signal('Todas');
  readonly redemptionFilter = signal('Pendentes');
  readonly deposits = [
    {
      time: '15:42',
      student: 'Ana Clara M.',
      className: '9º A',
      item: 'Celular',
      points: '+120',
      status: 'Validado',
    },
    {
      time: '14:18',
      student: 'Lucas P.',
      className: '8º B',
      item: 'Cabo USB',
      points: '+45',
      status: 'Validado',
    },
    {
      time: '11:07',
      student: 'Perfil da turma',
      className: '7º A',
      item: 'Mouse',
      points: '+70',
      status: 'Só turma',
    },
    {
      time: '09:35',
      student: 'Marina S.',
      className: '9º A',
      item: 'Pilha',
      points: '+30',
      status: 'Revisão',
    },
  ];
  readonly discardStats = { total: 1284, today: 32, week: 184 };
  readonly helpRequests = signal([
    {
      id: 'AJ-104',
      place: 'Totem Biblioteca',
      reason: 'Item não reconhecido após nova tentativa',
      time: 'Há 4 min',
      priority: 'Alta',
      status: 'Aguardando',
    },
    {
      id: 'AJ-103',
      place: 'Totem Pátio',
      reason: 'Aluno pediu acompanhamento de um adulto',
      time: 'Há 18 min',
      priority: 'Média',
      status: 'Em atendimento',
    },
    {
      id: 'AJ-101',
      place: 'Totem Biblioteca',
      reason: 'Porta não confirmou o fechamento',
      time: 'Hoje, 09:12',
      priority: 'Baixa',
      status: 'Resolvida',
    },
  ]);
  readonly redemptions = signal([
    {
      id: 'RG-208',
      code: 'B7K4-92',
      student: 'Ana Clara M.',
      className: '9º A',
      reward: 'Suco natural',
      requestedAt: 'Hoje, 15:31',
      expiresAt: 'Amanhã, 15:31',
      status: 'Pendente',
    },
    {
      id: 'RG-207',
      code: 'M2P8-41',
      student: 'Lucas P.',
      className: '8º B',
      reward: 'Caneta temática',
      requestedAt: 'Hoje, 13:46',
      expiresAt: 'Amanhã, 13:46',
      status: 'Pendente',
    },
    {
      id: 'RG-205',
      code: 'Q6T3-18',
      student: 'Marina S.',
      className: '9º A',
      reward: 'Ticket da cantina',
      requestedAt: 'Hoje, 10:12',
      expiresAt: 'Amanhã, 10:12',
      status: 'Pendente',
    },
    {
      id: 'RG-201',
      code: 'H9C5-73',
      student: 'Rafael G.',
      className: '7º A',
      reward: 'Caneta temática',
      requestedAt: 'Hoje, 08:20',
      expiresAt: 'Entregue às 09:04',
      status: 'Entregue',
    },
  ]);
  readonly machines = [
    {
      name: 'Totem Biblioteca',
      code: 'BT-001',
      status: 'Online',
      color: '#39d353',
      ink: '#176e2a',
      bg: '#e8faec',
      lastSeen: 'Agora · 16:40',
      camera: 'Disponível',
      door: 'Fechada',
      deposits: '18 hoje',
      version: 'v0.8.0',
    },
    {
      name: 'Totem Pátio',
      code: 'BT-002',
      status: 'Com problema',
      color: '#ffb020',
      ink: '#785510',
      bg: '#fff5d9',
      lastSeen: 'Há 2 min · 16:38',
      camera: 'Disponível',
      door: 'Aberta',
      deposits: '11 hoje',
      version: 'v0.8.0',
    },
    {
      name: 'Totem Laboratório',
      code: 'BT-003',
      status: 'Offline',
      color: '#e52b3a',
      ink: '#9c2030',
      bg: '#fff0f2',
      lastSeen: 'Há 38 min · 16:02',
      camera: 'Sem resposta',
      door: 'Indefinido',
      deposits: '3 hoje',
      version: 'v0.7.4',
    },
  ];
  readonly schools = signal([
    {
      name: 'Colégio ENIAC',
      city: 'Guarulhos · SP',
      students: '428 alunos',
      machines: '3 Totens',
      status: 'Ativa',
    },
    {
      name: 'Escola Horizonte',
      city: 'São Paulo · SP',
      students: '312 alunos',
      machines: '2 Totens',
      status: 'Implantação',
    },
    {
      name: 'Instituto Nova Geração',
      city: 'Campinas · SP',
      students: '506 alunos',
      machines: '3 Totens',
      status: 'Ativa',
    },
  ]);
  readonly demoClasses = signal([
    { name: '9º A', students: '31 alunos', xp: '12.480 XP', participation: '84%', status: 'Ativa' },
    { name: '8º B', students: '29 alunos', xp: '10.920 XP', participation: '79%', status: 'Ativa' },
    { name: '7º A', students: '33 alunos', xp: '9.740 XP', participation: '72%', status: 'Ativa' },
  ]);
  readonly administrators = signal([
    {
      name: 'Gustavo Alencar',
      email: 'alencar@bingo.demo',
      role: 'ADMIN_B',
      scope: 'Colégio ENIAC',
      status: 'Ativo',
    },
    {
      name: 'Paula Mendes',
      email: 'paula@eniac.demo',
      role: 'ADMIN_C',
      scope: 'Colégio ENIAC',
      status: 'Ativa',
    },
    {
      name: 'Equipe BinGo',
      email: 'admin@bingo.demo',
      role: 'ADMIN_A',
      scope: 'Global',
      status: 'Ativa',
    },
  ]);
  readonly products = signal([
    { name: 'Suco natural', price: '120 BinCoins', stock: '18 unidades', status: 'Ativo' },
    { name: 'Caneta temática', price: '90 BinCoins', stock: '7 unidades', status: 'Ativa' },
    { name: 'Ticket da cantina', price: '160 BinCoins', stock: 'Ilimitado', status: 'Ativo' },
    { name: 'Prêmio surpresa', price: '240 BinCoins', stock: 'Sem estoque', status: 'Inativo' },
  ]);
  readonly missions = signal([
    { name: 'Circuito dos cabos', type: 'Missão semanal', period: '18–25 set', status: 'Ativa' },
    { name: 'Alerta SCR4P', type: 'Evento global', period: '28 set', status: 'Pendente' },
  ]);
  readonly economySettings = signal([
    {
      title: 'Valor-base por descarte',
      value: '30',
      unit: 'pontos',
      description: 'Usado como referência antes dos bônus ambientais.',
      icon: 'gauge',
    },
    {
      title: 'Teto do BinBazar',
      value: '300',
      unit: 'BinCoins',
      description: 'Preço máximo permitido para produtos escolares.',
      icon: 'badge-dollar-sign',
    },
    {
      title: 'Bônus por categoria',
      value: '2',
      unit: '×',
      description: 'Taxa global aplicada conforme a categoria ambiental.',
      icon: 'leaf',
    },
    {
      title: 'Meta territorial',
      value: '8',
      unit: 'descartes',
      description: 'Referência atual para avanço de cenário.',
      icon: 'map',
    },
  ]);
  constructor() {
    effect(() => {
      if (!this.auth.admin()) {
        this.activeOperation.set(null);
        this.redemptionToDeliver.set(null);
        this.toast.set('');
      }
    });
  }
  open(action: string, index: number | null = null, key: string | null = null) {
    this.activeOperation.set({ action, index, key });
  }
  close() {
    this.activeOperation.set(null);
  }
  pendingRedemptions() {
    return this.redemptions().filter((x) => x.status === 'Pendente').length;
  }
  openHelp() {
    return this.helpRequests().filter((x) => x.status !== 'Resolvida').length;
  }
  notify(message: string) {
    this.toast.set(message);
    window.setTimeout(() => this.toast.set(''), 2600);
  }
  submit(form: HTMLFormElement) {
    const op = this.activeOperation();
    if (!op) return;
    const v = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
    const i = op.index ?? 0;
    switch (op.action) {
      case 'product-create':
        this.products.update((a) => [
          ...a,
          {
            name: v['name'],
            price: `${v['price']} BinCoins`,
            stock: `${v['stock']} unidades`,
            status: v['status'],
          },
        ]);
        break;
      case 'product-edit':
        this.products.update((a) =>
          a.map((x, n) =>
            n === i
              ? {
                  ...x,
                  name: v['name'],
                  price: `${v['price']} BinCoins`,
                  stock: v['stock'] === 'Ilimitado' ? v['stock'] : `${v['stock']} unidades`,
                  status: v['status'],
                }
              : x,
          ),
        );
        break;
      case 'admin-create':
        this.administrators.update((a) => [
          ...a,
          {
            name: v['name'],
            email: v['email'],
            role: v['role'],
            scope: this.role() === 'ADMIN_A' ? 'Global' : 'Colégio ENIAC',
            status: v['status'],
          },
        ]);
        break;
      case 'admin-open':
        this.administrators.update((a) => a.map((x) => (x.email === op.key ? { ...x, ...v } : x)));
        break;
      case 'redemption-cancel':
        this.redemptions.update((a) =>
          a.map((x) =>
            x.id === op.key ? { ...x, status: 'Cancelado', expiresAt: 'Cancelado agora' } : x,
          ),
        );
        break;
      case 'school-create':
        this.schools.update((a) => [
          ...a,
          {
            name: v['name'],
            city: v['city'],
            students: '0 alunos',
            machines: '0 Totens',
            status: v['status'],
          },
        ]);
        break;
      case 'school-open':
        this.schools.update((a) => a.map((x) => (x.name === op.key ? { ...x, ...v } : x)));
        break;
      case 'mission-create':
        this.missions.update((a) => [
          ...a,
          { name: v['name'], type: v['type'], period: v['period'], status: v['status'] },
        ]);
        break;
      case 'mission-edit':
        this.missions.update((a) => a.map((x, n) => (n === i ? { ...x, ...v } : x)));
        break;
      case 'economy-edit':
        this.economySettings.update((a) =>
          a.map((x, n) => (n === i ? { ...x, value: v['value'] } : x)),
        );
        break;
    }
    const titles: Record<string, string> = {
      'product-create': 'Cadastrar produto',
      'product-edit': 'Editar produto e estoque',
      'admin-create': 'Cadastrar administrador',
      'admin-open': 'Gerenciar administrador',
      'redemption-cancel': 'Cancelar resgate reservado',
      'school-create': 'Cadastrar escola',
      'school-open': 'Detalhes da escola',
      'mission-create': 'Criar missão global',
      'mission-edit': 'Editar missão global',
      'economy-edit': 'Editar regra econômica',
    };
    this.close();
    this.notify(`${titles[op.action] || 'Operação'} concluído somente nesta demonstração.`);
  }
}
