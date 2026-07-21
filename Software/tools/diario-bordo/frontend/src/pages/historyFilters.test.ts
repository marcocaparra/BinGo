import { describe, expect, it } from 'vitest'
import { filterHistoryReports } from './historyFilters'

const reports = [
  { memberName: 'Marco Caparra', area: 'Gestão', status: 'NO_ACTIVITY' as const },
  { memberName: 'Gustavo Alencar', area: 'Design', status: 'SUBMITTED' as const },
]

describe('history filters', () => {
  it('keeps no-activity records visible when no status is selected', () => {
    expect(filterHistoryReports(reports, { member: '', area: '', status: '' }))
      .toEqual(reports)
  })

  it('filters no-activity records when that status is selected', () => {
    expect(filterHistoryReports(reports, { member: '', area: '', status: 'NO_ACTIVITY' }))
      .toEqual([reports[0]])
  })
})
