import { useEffect, useState } from 'react'

const DEFAULT_ROUTE = 'item'

function currentRoute() {
  const hash = window.location.hash.replace('#', '')
  return hash || DEFAULT_ROUTE
}

export function useHashRoute() {
  const [route, setRoute] = useState(currentRoute)

  useEffect(() => {
    function handleHashChange() {
      setRoute(currentRoute())
    }
    window.addEventListener('hashchange', handleHashChange)
    return () => window.removeEventListener('hashchange', handleHashChange)
  }, [])

  return route
}
