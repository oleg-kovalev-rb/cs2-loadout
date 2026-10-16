import { useEffect, useState } from 'react'

function mapProfiles(raw) {
  return Object.fromEntries(
    Object.entries(raw || {}).map(([steamId, profile]) => [
      steamId,
      { nickname: profile.nickname, avatarUrl: profile.avatar_url },
    ]),
  )
}

// app_core-owned enrichment (nickname/avatar) for a page of steam_ids —
// the one sanctioned non-app_fetcher data source for this island. See
// agent/styleguides/core/architecture-layers.md's "App_core-Owned
// Enrichment (Public Pages)" carve-out. Its failure is deliberately
// non-fatal: the page falls back to steam_id + a letter avatar rather
// than entering its error state.
export function useInventoryProfiles(steamIds) {
  const [profiles, setProfiles] = useState({})
  // Keyed on the joined id list so a page change (a new set of ids)
  // re-fetches without the effect depending on the array identity.
  const key = steamIds.join('|')

  useEffect(() => {
    if (key === '') {
      setProfiles({})
      return
    }

    let cancelled = false
    const query = key
      .split('|')
      .map((id) => `steam_ids[]=${encodeURIComponent(id)}`)
      .join('&')

    fetch(`/inventories/profiles?${query}`, { headers: { Accept: 'application/json' } })
      .then((response) => (response.ok ? response.json() : { profiles: {} }))
      .then((payload) => {
        if (!cancelled) setProfiles(mapProfiles(payload.profiles))
      })
      .catch(() => {
        if (!cancelled) setProfiles({})
      })

    return () => {
      cancelled = true
    }
  }, [key])

  return profiles
}
