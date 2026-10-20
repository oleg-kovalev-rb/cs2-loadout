import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { Application } from '@hotwired/stimulus'
import { DEFAULT_DELAY_MS, EXIT_DURATION_MS, FlashController } from '../flash_controller'

describe('FlashController', () => {
  let application

  beforeEach(() => {
    vi.useFakeTimers()
    application = Application.start()
    application.register('flash', FlashController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ''
    vi.useRealTimers()
  })

  function mountFlash(delay = DEFAULT_DELAY_MS) {
    document.body.innerHTML = `
      <div class="flash-stack">
        <div class="flash" data-controller="flash" data-flash-delay-value="${delay}">
          Message
        </div>
      </div>
    `

    return document.querySelector('.flash')
  }

  test('marks the toast as leaving after the configured delay', async () => {
    const toast = mountFlash(1000)
    await vi.advanceTimersByTimeAsync(0)

    await vi.advanceTimersByTimeAsync(1000)

    expect(toast.classList.contains('is-leaving')).toBe(true)
    expect(document.body.contains(toast)).toBe(true)
  })

  test('removes the toast after its exit transition', async () => {
    const toast = mountFlash(1000)
    await vi.advanceTimersByTimeAsync(0)

    await vi.advanceTimersByTimeAsync(1000 + EXIT_DURATION_MS)

    expect(document.body.contains(toast)).toBe(false)
  })

  test('does not dismiss after the controller disconnects', async () => {
    const toast = mountFlash(1000)
    await vi.advanceTimersByTimeAsync(0)

    toast.remove()
    await vi.advanceTimersByTimeAsync(0)
    await vi.advanceTimersByTimeAsync(1000)

    expect(toast.classList.contains('is-leaving')).toBe(false)
  })
})
