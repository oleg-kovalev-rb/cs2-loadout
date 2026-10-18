export function hasPartialPoints(points) {
  return Array.isArray(points) && points.some((point) => point?.complete === false)
}

export function partialPointLabel(point) {
  if (point?.pricedItemsCount != null && point?.pricableItemsCount != null) {
    return `Partial estimate · ${point.pricedItemsCount}/${point.pricableItemsCount} priced`
  }

  return 'Partial estimate'
}
