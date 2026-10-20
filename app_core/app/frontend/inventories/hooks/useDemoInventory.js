import { useEffect, useState } from 'react'
import { fetchJson } from '../../shared/utils/fetchJson'
import { mapInventory } from './useInventoryCatalog'

// The demo card is additive: a failed demo summary must not take down the
// public inventories page. It simply does not render.
export function useDemoInventory(fetcherUrl, demo, demoToken) {
  const [inventory, setInventory] = useState(null)

  useEffect(() => {
    if (!demo || !demoToken) {
      setInventory(null)
      return undefined
    }

    let cancelled = false

    fetchJson(`${fetcherUrl}/api/demo/inventory_summary`, {
      headers: { Accept: 'application/json', Authorization: `Bearer ${demoToken}` },
    })
      .then((raw) => {
        if (!cancelled) setInventory(mapInventory(raw))
      })
      .catch(() => {
        if (!cancelled) setInventory(null)
      })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, demo, demoToken])

  return inventory
}
