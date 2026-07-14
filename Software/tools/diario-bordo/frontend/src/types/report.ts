export type ReportStatus =
  | 'SUBMITTED'
  | 'SUBMITTED_LATE'
  | 'NO_ACTIVITY'

export type DailyReport = {
  id: string
  memberId: string
  memberName: string
  reportDate: string
  area: string
  title: string
  description: string
  problems?: string | null
  solution?: string | null
  nextSteps?: string | null
  evidenceLinks?: string | null
  timeSpentMinutes?: number | null
  approximateTime?: string | null
  participants?: string | null
  environment?: string | null
  recordType?: string | null
  decisions?: string | null
  testsAndObservations?: string | null
  toolsUsed?: string | null
  pendingItems?: string | null
  nextStepOwner?: string | null
  nextStepDueDate?: string | null
  finalNotes?: string | null
  attachments?: ReportAttachment[]
  status: ReportStatus
  submittedAt: string
  createdAt?: string
  updatedAt?: string
}

export type CreateTodayReportRequest = {
  memberId: string
  reportDate: string
  area: string
  title: string
  description: string
  problems: string
  solution?: string
  evidenceLinks: string
  participants?: string
  environment: string
  recordType: string
  decisions: string
  testsAndObservations: string
  toolsUsed?: string
  pendingItems?: string
  finalNotes?: string
}

export type ReportAttachment = {
  id: string
  originalFilename: string
  contentType: string
  sizeBytes: number
  category: string
  downloadUrl: string
  uploadedAt: string
}

export type ReportExistence = {
  exists: boolean
  reportId?: string | null
  memberId: string
  memberName?: string | null
  reportDate: string
}

export type UpdateDailyReportRequest = {
  area: string
  title: string
  description: string
  problems: string
  evidenceLinks: string
  participants?: string
  environment: string
  recordType: string
  decisions: string
  testsAndObservations: string
  toolsUsed?: string
  pendingItems?: string
  finalNotes?: string
}

export type CreateNoActivityReportRequest = {
  memberId: string
  reportDate: string
  area?: string
}
