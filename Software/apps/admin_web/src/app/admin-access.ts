export type AdminRole = 'ADMIN_A' | 'ADMIN_B' | 'ADMIN_C';

export type AdminView =
  | 'overview'
  | 'schools'
  | 'administrators'
  | 'students'
  | 'classes'
  | 'pending'
  | 'requests'
  | 'deposits'
  | 'help'
  | 'products'
  | 'redemptions'
  | 'missions'
  | 'machines'
  | 'economy';

export interface AdminRoleDefinition {
  code: AdminRole;
  label: string;
  shortLabel: string;
  scope: string;
  description: string;
  operatorName: string;
  operatorInitials: string;
  views: readonly AdminView[];
}

export const ADMIN_ROLES: Record<AdminRole, AdminRoleDefinition> = {
  ADMIN_A: {
    code: 'ADMIN_A',
    label: 'Administrador global BinGo',
    shortLabel: 'Admin A · Global',
    scope: 'Ecossistema BinGo',
    description: 'Escolas, administradores, Totens, Missões e configurações globais.',
    operatorName: 'Equipe BinGo',
    operatorInitials: 'BG',
    views: ['overview', 'schools', 'administrators', 'machines', 'missions', 'economy'],
  },
  ADMIN_B: {
    code: 'ADMIN_B',
    label: 'Administrador da escola',
    shortLabel: 'Admin B · Escola',
    scope: 'Colégio ENIAC',
    description: 'Gestão de alunos, turmas, equipe operacional, pendências e BinBazar.',
    operatorName: 'Gustavo Alencar',
    operatorInitials: 'GA',
    views: [
      'overview',
      'students',
      'classes',
      'administrators',
      'pending',
      'deposits',
      'help',
      'products',
      'redemptions',
      'missions',
      'machines',
    ],
  },
  ADMIN_C: {
    code: 'ADMIN_C',
    label: 'Operador da escola',
    shortLabel: 'Admin C · Operação',
    scope: 'Colégio ENIAC',
    description: 'Consultas, solicitações, estoque, resgates e operação diária dos Totens.',
    operatorName: 'Gustavo Alencar',
    operatorInitials: 'GA',
    views: [
      'overview',
      'students',
      'requests',
      'deposits',
      'help',
      'products',
      'redemptions',
      'machines',
    ],
  },
};

export function canAccessView(role: AdminRole, view: AdminView): boolean {
  return ADMIN_ROLES[role].views.includes(view);
}

export function firstViewForRole(role: AdminRole): AdminView {
  return ADMIN_ROLES[role].views[0];
}
