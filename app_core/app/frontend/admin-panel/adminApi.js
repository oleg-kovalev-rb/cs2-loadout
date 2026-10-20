import { fetchJson } from '../shared/utils/fetchJson'

function authHeaders(bridgeToken) {
  return { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` }
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
