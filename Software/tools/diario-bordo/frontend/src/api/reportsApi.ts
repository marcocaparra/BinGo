import type {
  CreateNoActivityReportRequest,
  CreateTodayReportRequest,
  DailyReport,
} from '../types/report'
import { request } from './httpClient'

export function getReports(): Promise<DailyReport[]> {
  return request<DailyReport[]>('/reports')
}

export function createTodayReport(
  payload: CreateTodayReportRequest,
): Promise<DailyReport> {
  return request<DailyReport>('/reports/today', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

export function createNoActivityReport(
  payload: CreateNoActivityReportRequest,
): Promise<DailyReport> {
  return request<DailyReport>('/reports/no-activity', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}
