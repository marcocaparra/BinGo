const configuredBaseUrl = import.meta.env.VITE_API_BASE_URL?.trim()

export const API_BASE_URL = (
  configuredBaseUrl || 'http://127.0.0.1:8080'
).replace(/\/+$/, '')

export const ATTACHMENTS_ENABLED = import.meta.env.VITE_ATTACHMENTS_ENABLED === 'true'
