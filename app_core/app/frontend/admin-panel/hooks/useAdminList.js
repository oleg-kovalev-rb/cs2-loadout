import { useEffect, useState, useCallback } from 'react'
import { adminGet } from '../adminApi'

export function useAdminList(fetcherUrl, bridgeToken, resourcePath, { page, perPage }) {
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState(null)
  const [reloadToken, setReloadToken] = useState(0)

  useEffect(() => {
    let cancelled = false
    setStatus('loading')

    const query = new URLSearchParams({ page, per_page: perPage }).toString()

    adminGet(fetcherUrl, bridgeToken, `${resourcePath}?${query}`)
      .then((body) => {
        if (cancelled) return
        setData(body)
        setStatus('success')
      })
      .catch((err) => {
        if (cancelled) return
        setError(err)
        setStatus('error')
      })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken, resourcePath, page, perPage, reloadToken])

  const refetch = useCallback(() => setReloadToken((token) => token + 1), [])

  return { data, meta: data?.meta ?? null, status, error, refetch }
}
