export async function fetchJson(url, options = {}) {
  const response = await fetch(url, options)
  const body = await response.json().catch(() => ({}))

  if (!response.ok) {
    throw new Error(body.message || `Request to ${url} failed: ${response.status}`)
  }

  return body
}
