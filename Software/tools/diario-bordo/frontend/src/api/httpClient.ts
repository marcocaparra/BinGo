import { API_BASE_URL } from '../config/api'
import { getStoredSession } from '../auth/session'

function getErrorMessage(body: unknown): string | null {
  if (
    typeof body === 'object' &&
    body !== null &&
    'error' in body &&
    typeof body.error === 'string'
  ) {
    return body.error
  }

  return null
}

export async function request<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const headers = new Headers(options.headers)

  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json')
  }

  const session = getStoredSession()
  if (session && !headers.has('X-Diary-Password')) {
    headers.set('X-Diary-Password', session.pin)
  }

  let response: Response

  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
    })
  } catch {
    throw new Error('Não foi possível conectar à API do Diário de Bordo.')
  }

  if (!response.ok) {
    let message = 'Erro ao comunicar com a API.'

    try {
      message = getErrorMessage(await response.json()) ?? message
    } catch {
      // A resposta pode não ter corpo JSON.
    }

    throw new Error(message)
  }

  return response.json() as Promise<T>
}

export async function requestText(
  path: string,
  options: RequestInit = {},
): Promise<string> {
  const headers = new Headers(options.headers)
  const session = getStoredSession()
  if (session && !headers.has('X-Diary-Password')) {
    headers.set('X-Diary-Password', session.pin)
  }

  let response: Response

  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
    })
  } catch {
    throw new Error('Não foi possível conectar à API do Diário de Bordo.')
  }

  if (!response.ok) {
    let message = 'Erro ao comunicar com a API.'

    try {
      message = getErrorMessage(await response.json()) ?? message
    } catch {
      // A resposta pode não ter corpo JSON.
    }

    throw new Error(message)
  }

  return response.text()
}

export async function requestVoid(
  path: string,
  options: RequestInit = {},
): Promise<void> {
  const headers = new Headers(options.headers)
  const session = getStoredSession()
  if (session && !headers.has('X-Diary-Password')) {
    headers.set('X-Diary-Password', session.pin)
  }

  let response: Response

  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
    })
  } catch {
    throw new Error('Não foi possível conectar à API do Diário de Bordo.')
  }

  if (!response.ok) {
    let message = 'Erro ao comunicar com a API.'

    try {
      message = getErrorMessage(await response.json()) ?? message
    } catch {
      // A resposta pode não ter corpo JSON.
    }

    throw new Error(message)
  }
}
