import { RANGE_MS } from '../chartConfig'
import { sumAsOfEachHour } from './bucketing'

export function portfolioSeries(items) {
  const currentValueCents = items.reduce((sum, item) => sum + (item.currentPriceCents || 0), 0)
  const itemPointLists = items.map((item) => item.priceHistory)

  const series = {}
  for (const range of Object.keys(RANGE_MS)) {
    series[range] = sumAsOfEachHour(itemPointLists, RANGE_MS[range], (point) => point.priceCents)
  }

  return { currentValueCents, series }
}
