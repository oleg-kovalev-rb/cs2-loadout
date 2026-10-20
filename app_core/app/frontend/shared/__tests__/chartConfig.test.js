import { describe, test, expect } from 'vitest'
import { generateAxisLabels, PERIOD_MS } from '../chartConfig'

const DAY = 24 * 60 * 60 * 1000
const NOW = Date.UTC(2026, 9, 20, 6, 30)

describe('generateAxisLabels', () => {
  test('keeps the canonical labels when the series covers the period', () => {
    expect(generateAxisLabels('7d', NOW - 7.25 * DAY, NOW)).toEqual([
      '7d ago',
      '5d ago',
      '4d ago',
      '2d ago',
      'today',
    ])
    expect(generateAxisLabels('30d', NOW - 30.25 * DAY, NOW)).toEqual([
      '30d ago',
      '23d ago',
      '15d ago',
      '8d ago',
      'today',
    ])
    expect(generateAxisLabels('1y', NOW - 364.25 * DAY, NOW)).toEqual([
      '12mo ago',
      '9mo ago',
      '6mo ago',
      '3mo ago',
      'today',
    ])
    expect(generateAxisLabels('24h', NOW - DAY, NOW)).toEqual([
      '24h ago',
      '18h ago',
      '12h ago',
      '6h ago',
      'now',
    ])
  })

  test('sizes the labels from the real span when the series is shorter', () => {
    expect(generateAxisLabels('7d', NOW - 2 * DAY, NOW)).toEqual([
      '48h ago',
      '36h ago',
      '24h ago',
      '12h ago',
      'today',
    ])
    expect(generateAxisLabels('1y', NOW - 90 * DAY, NOW)).toEqual([
      '90d ago',
      '68d ago',
      '45d ago',
      '23d ago',
      'today',
    ])
  })

  test('falls back to the nominal period when there is no span', () => {
    expect(generateAxisLabels('7d', NOW - PERIOD_MS['7d'], NOW)).toEqual([
      '7d ago',
      '5d ago',
      '4d ago',
      '2d ago',
      'today',
    ])
  })

  test("leaves 'all' blank except the trailing today", () => {
    expect(generateAxisLabels('all', NOW - 100 * DAY, NOW)).toEqual(['', '', '', '', 'today'])
  })
})
