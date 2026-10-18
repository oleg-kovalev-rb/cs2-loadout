import { Fragment, useReducer, useState } from 'react'
import { userInventoriesReducer, initialState } from './userInventoriesReducer'
import { useAdminList } from '../hooks/useAdminList'
import { adminGet, adminSend } from '../adminApi'
import { Pagination } from '../components/Pagination'
import { fmtDateTime } from '../utils/format'

const VISIBLE_ITEMS = 2

// Deliberately not `fmtPrice`: that helper treats 0 and null/undefined the
// same (both render as "—"), which is correct for a price that simply
// hasn't loaded yet, but wrong here — total_value_cents distinguishes a
// confirmed-empty/worthless inventory (0, a real value) from one that has
// never been synced to a value log at all (null), and those must render
// differently.
function fmtValueOrDash(cents) {
  if (cents == null) return '—'
  return (
    '$' +
    (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  )
}

export function UserInventoriesPage({ fetcherUrl, bridgeToken }) {
  const [state, dispatch] = useReducer(userInventoriesReducer, initialState)
  const { data, status, refetch } = useAdminList(
    fetcherUrl,
    bridgeToken,
    '/api/admin/user_inventories',
    {
      page: state.page,
      perPage: state.perPage,
    },
  )
  const [detailsBySteamId, setDetailsBySteamId] = useState({})

  if (status === 'loading' && !data) return <div className="page-placeholder">Loading…</div>
  if (status === 'error' && !data)
    return <div className="page-placeholder">Couldn&rsquo;t load UserInventory</div>

  const userInventories = data?.user_inventories ?? []
  const meta = data?.meta ?? { total_count: 0, total_pages: 0 }
  const allSteamIds = userInventories.map((inv) => inv.steam_id)
  const allSelected = allSteamIds.length > 0 && allSteamIds.every((id) => state.selectedIds.has(id))

  async function handleExpandToggle(steamId) {
    dispatch({ type: 'ROW_EXPAND_TOGGLED', steamId })

    if (!detailsBySteamId[steamId]) {
      setDetailsBySteamId((prev) => ({ ...prev, [steamId]: { status: 'loading', items: [] } }))
      const body = await adminGet(fetcherUrl, bridgeToken, `/api/admin/user_inventories/${steamId}`)
      setDetailsBySteamId((prev) => ({
        ...prev,
        [steamId]: { status: 'success', items: body.user_inventory.items },
      }))
    }
  }

  async function handleSync(steamId) {
    await adminSend(fetcherUrl, bridgeToken, 'POST', `/api/admin/user_inventories/${steamId}/sync`)
    refetch()
  }

  async function handleDelete(steamId) {
    await adminSend(fetcherUrl, bridgeToken, 'DELETE', `/api/admin/user_inventories/${steamId}`)
    refetch()
  }

  async function handleBulkWarmCache() {
    await adminSend(
      fetcherUrl,
      bridgeToken,
      'POST',
      '/api/admin/user_inventories/bulk_warm_cache',
      {
        steam_ids: [...state.selectedIds],
      },
    )
    dispatch({ type: 'SELECTION_CLEARED' })
  }

  return (
    <section className="page">
      <div className="page-head">
        <h1>UserInventory</h1>
      </div>
      <div className="resource">
        <div className="resource-head">
          <h2>All records</h2>
          <div className="resource-head-right">
            <span className="sel-count">
              {state.selectedIds.size > 0 ? `Selected: ${state.selectedIds.size}` : ''}
            </span>
            <button
              type="button"
              className="btn ghost-cache cache-action"
              disabled={state.selectedIds.size === 0}
              onClick={handleBulkWarmCache}
            >
              Warm cache
            </button>
          </div>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th className="col-check">
                  <input
                    type="checkbox"
                    className="select-all"
                    aria-label="Select all"
                    checked={allSelected}
                    onChange={(event) =>
                      dispatch({
                        type: 'ALL_TOGGLED',
                        checked: event.target.checked,
                        steamIds: allSteamIds,
                      })
                    }
                  />
                </th>
                <th />
                <th>Steam ID</th>
                <th>Items</th>
                <th>Value</th>
                <th>Synced</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {userInventories.map((inv) => {
                const isExpanded = state.expandedSteamIds.has(inv.steam_id)
                const detail = detailsBySteamId[inv.steam_id]
                return (
                  <Fragment key={inv.steam_id}>
                    <tr>
                      <td className="col-check">
                        <input
                          type="checkbox"
                          className="row-check"
                          aria-label={`Select ${inv.steam_id}`}
                          checked={state.selectedIds.has(inv.steam_id)}
                          onChange={() => dispatch({ type: 'ROW_TOGGLED', steamId: inv.steam_id })}
                        />
                      </td>
                      <td>
                        <button
                          type="button"
                          className="icon-btn expand"
                          aria-label={`Show items for ${inv.steam_id}`}
                          aria-expanded={isExpanded}
                          onClick={() => handleExpandToggle(inv.steam_id)}
                        >
                          {isExpanded ? '▾' : '▸'}
                        </button>
                      </td>
                      <td className="mono">{inv.steam_id}</td>
                      <td className="mono">{inv.items_count}</td>
                      <td className="mono">{fmtValueOrDash(inv.total_value_cents)}</td>
                      <td className="mono text-muted">{fmtDateTime(inv.updated_at)}</td>
                      <td>
                        <div className="row-actions">
                          <button
                            type="button"
                            className="icon-btn"
                            title="Sync inventory now"
                            aria-label="Sync inventory now"
                            onClick={() => handleSync(inv.steam_id)}
                          >
                            ⟲
                          </button>
                          <button
                            type="button"
                            className="icon-btn danger"
                            aria-label={`Delete ${inv.steam_id}`}
                            onClick={() => handleDelete(inv.steam_id)}
                          >
                            ✕
                          </button>
                        </div>
                      </td>
                    </tr>
                    {isExpanded && (
                      <tr className="nested-row">
                        <td colSpan={7}>
                          <div className="nested-wrap open">
                            {!detail || detail.status === 'loading' ? (
                              <p className="text-muted">Loading…</p>
                            ) : (
                              <table>
                                <thead>
                                  <tr>
                                    <th>Item</th>
                                    <th>Added</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {detail.items.slice(0, VISIBLE_ITEMS).map((item, index) => (
                                    <tr key={index}>
                                      <td>{item.market_hash_name}</td>
                                      <td className="mono text-muted">
                                        {fmtDateTime(item.added_at)}
                                      </td>
                                    </tr>
                                  ))}
                                  {detail.items.length > VISIBLE_ITEMS && (
                                    <tr>
                                      <td className="text-muted">
                                        …and {detail.items.length - VISIBLE_ITEMS} more
                                      </td>
                                      <td />
                                    </tr>
                                  )}
                                </tbody>
                              </table>
                            )}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}
            </tbody>
          </table>
        </div>

        <Pagination
          page={state.page}
          perPage={state.perPage}
          totalCount={meta.total_count}
          totalPages={meta.total_pages}
          onPageChange={(page) => dispatch({ type: 'PAGE_CHANGED', page })}
          onPerPageChange={(perPage) => dispatch({ type: 'PER_PAGE_CHANGED', perPage })}
        />
      </div>
    </section>
  )
}
