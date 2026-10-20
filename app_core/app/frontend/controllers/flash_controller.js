import { Controller } from '@hotwired/stimulus'

export const DEFAULT_DELAY_MS = 5000
export const EXIT_DURATION_MS = 180

export class FlashController extends Controller {
  static values = { delay: Number }

  connect() {
    this.scheduleDismissal()
  }

  disconnect() {
    this.clearTimers()
  }

  scheduleDismissal() {
    this.clearTimers()
    this.dismissTimeout = window.setTimeout(
      () => this.dismiss(),
      this.delayValue || DEFAULT_DELAY_MS,
    )
  }

  dismiss() {
    this.clearTimers()
    this.element.classList.add('is-leaving')
    this.removeTimeout = window.setTimeout(() => this.element.remove(), EXIT_DURATION_MS)
  }

  clearTimers() {
    window.clearTimeout(this.dismissTimeout)
    window.clearTimeout(this.removeTimeout)
    this.dismissTimeout = undefined
    this.removeTimeout = undefined
  }
}
