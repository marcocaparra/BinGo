import { describe, expect, it, vi } from 'vitest'
import { waitForApiReady } from './healthApi'

describe('waitForApiReady', () => {
  it('retries while the free backend is waking up', async () => {
    const fetcher = vi.fn()
      .mockRejectedValueOnce(new Error('sleeping'))
      .mockResolvedValueOnce(new Response('', { status: 503 }))
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
    const wait = vi.fn().mockResolvedValue(undefined)

    const ready = await waitForApiReady(fetcher, wait, [2_000, 4_000, 8_000])

    expect(ready).toBe(true)
    expect(fetcher).toHaveBeenCalledTimes(3)
    expect(wait).toHaveBeenNthCalledWith(1, 2_000)
    expect(wait).toHaveBeenNthCalledWith(2, 4_000)
  })

  it('stops after the configured attempts', async () => {
    const fetcher = vi.fn().mockRejectedValue(new Error('offline'))
    const wait = vi.fn().mockResolvedValue(undefined)

    const ready = await waitForApiReady(fetcher, wait, [2_000, 4_000])

    expect(ready).toBe(false)
    expect(fetcher).toHaveBeenCalledTimes(3)
  })
})
