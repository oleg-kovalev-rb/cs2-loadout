function authHeaders(bridgeToken) {
  return { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` }
}

async function fetchJson(url, options) {
  const response = await fetch(url, options)
  const body = await response.json().catch(() => ({}))

  if (!response.ok) {
    throw new Error(body.message || `Request to ${url} failed: ${response.status}`)
  }

  return body
}

export function adminGet(fetcherUrl, bridgeToken, path) {
  return fetchJson(`${fetcherUrl}${path}`, { headers: authHeaders(bridgeToken) })
}

export function adminSend(fetcherUrl, bridgeToken, method, path, body) {
  return fetchJson(`${fetcherUrl}${path}`, {
    method,
    headers: { ...authHeaders(bridgeToken), 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}
