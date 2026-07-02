import type { DailyReport } from '../types/report'

export const members = ['Ana Souza', 'Bruno Lima', 'Camila Rocha', 'Diego Alves']

export const areas = ['Desenvolvimento', 'Design', 'Eletrônica', 'Gestão']

export const mockReports: DailyReport[] = [
  {
    id: 'report-1',
    memberName: 'Ana Souza',
    area: 'Desenvolvimento',
    reportDate: '2026-07-02',
    title: 'Estrutura inicial do frontend',
    description: 'Organizei as telas principais e defini a navegação da V0.',
    status: 'SUBMITTED',
    submittedAt: '2026-07-02T15:40:00-03:00',
  },
  {
    id: 'report-2',
    memberName: 'Bruno Lima',
    area: 'Eletrônica',
    reportDate: '2026-07-01',
    title: 'Teste do sensor de presença',
    description: 'Revisei as leituras do sensor e registrei os valores fora do padrão.',
    status: 'SUBMITTED_LATE',
    submittedAt: '2026-07-02T09:15:00-03:00',
  },
  {
    id: 'report-3',
    memberName: 'Camila Rocha',
    area: 'Design',
    reportDate: '2026-07-01',
    title: 'Revisão dos materiais da feira',
    description: 'Ajustei a hierarquia visual do banner e preparei uma nova versão.',
    status: 'SUBMITTED',
    submittedAt: '2026-07-01T18:20:00-03:00',
  },
  {
    id: 'report-4',
    memberName: 'Diego Alves',
    area: 'Gestão',
    reportDate: '2026-06-30',
    title: 'Sem atividade registrada',
    description: 'Integrante indicou que não realizou atividades nesta data.',
    status: 'NO_ACTIVITY',
    submittedAt: '2026-06-30T19:05:00-03:00',
  },
]

export const mockPendingReports: DailyReport[] = [
  {
    id: 'pending-1',
    memberName: 'Bruno Lima',
    area: 'Eletrônica',
    reportDate: '2026-07-02',
    title: 'Relatório pendente',
    description: 'Nenhum registro foi enviado para esta data.',
    status: 'PENDING',
  },
  {
    id: 'pending-2',
    memberName: 'Camila Rocha',
    area: 'Design',
    reportDate: '2026-07-02',
    title: 'Relatório pendente',
    description: 'Nenhum registro foi enviado para esta data.',
    status: 'PENDING',
  },
  {
    id: 'pending-3',
    memberName: 'Diego Alves',
    area: 'Gestão',
    reportDate: '2026-07-01',
    title: 'Relatório pendente',
    description: 'Nenhum registro foi enviado para esta data.',
    status: 'PENDING',
  },
]
