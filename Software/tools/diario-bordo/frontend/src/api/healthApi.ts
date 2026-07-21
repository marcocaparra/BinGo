import { API_BASE_URL } from '../config/api'

export const HEALTH_RETRY_DELAYS = [2_000, 4_000, 8_000, 12_000]

type Fetcher = typeof fetch
type Wait = (milliseconds: number) => Promise<void>

const defaultWait: Wait = (milliseconds) => new Promise((resolve) => {
  window.setTimeout(resolve, milliseconds)
})

export async function waitForApiReady(
  fetcher: Fetcher = fetch,
  wait: Wait = defaultWait,
  retryDelays: number[] = HEALTH_RETRY_DELAYS,
): Promise<boolean> {
  for (let attempt = 0; attempt <= retryDelays.length; attempt += 1) {
    try {
      const response = await fetcher(`${API_BASE_URL}/health`, { cache: 'no-store' })
      if (response.ok) {
        return true
      }
    } catch {
      // O backend gratuito pode estar iniciando; a próxima tentativa continua o fluxo.
    }

    if (attempt < retryDelays.length) {
      await wait(retryDelays[attempt])
    }
  }

  return false
}
