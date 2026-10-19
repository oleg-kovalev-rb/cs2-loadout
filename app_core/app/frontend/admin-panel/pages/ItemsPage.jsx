import { useEffect, useReducer, useState } from 'react'
import { itemsReducer, initialState } from './itemsReducer'
import { useAdminList } from '../hooks/useAdminList'
import { adminSend } from '../adminApi'
import { Pagination } from '../components/Pagination'
import { fmtPrice } from '../utils/format'
import { changePercent } from '../utils/change'
import { trendDirection } from '../../shared/utils/trend'

function Swatch({ iconUrl }) {
  if (iconUrl) return <img className="swatch" src={iconUrl} alt="" />
  return <span className="swatch" aria-hidden="true" />
}

export function ItemsPage({ fetcherUrl, bridgeToken }) {
  const [state, dispatch] = useReducer(itemsReducer, initialState)
  const { data, status, refetch } = useAdminList(fetcherUrl, bridgeToken, '/api/admin/items', {
    page: state.page,
    perPage: state.perPage,
  })
  const [createName, setCreateName] = useState('')
  const [createError, setCreateError] = useState(null)
  const [actionError, setActionError] = useState(null)

  useEffect(() => {
    function handleOutsideClick(event) {
      if (!event.target.closest('.menu-wrap')) dispatch({ type: 'ALL_MENUS_CLOSED' })
    }
    function handleEscape(event) {
      if (event.key === 'Escape') dispatch({ type: 'ALL_MENUS_CLOSED' })
    }
    document.addEventListener('click', handleOutsideClick)
    document.addEventListener('keydown', handleEscape)
    return () => {
      document.removeEventListener('click', handleOutsideClick)
      document.removeEventListener('keydown', handleEscape)
    }
  }, [])

  if (status === 'loading' && !data) return <div className="page-placeholder">Loading…</div>
  if (status === 'error' && !data)
    return <div className="page-placeholder">Couldn&rsquo;t load Item</div>

  const items = data?.items ?? []
  const meta = data?.meta ?? { total_count: 0, total_pages: 0 }
  const allIds = items.map((item) => item.id)
  const allSelected = allIds.length > 0 && allIds.every((id) => state.selectedIds.has(id))

  async function handleCreateSubmit(event) {
    event.preventDefault()
    setCreateError(null)
    setActionError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items', {
        item: { market_hash_name: createName },
      })
      setCreateName('')
      dispatch({ type: 'CREATE_PANEL_CLOSED' })
      refetch()
    } catch (err) {
      setCreateError(err.message)
    }
  }

  async function handleDelete(id) {
    setActionError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'DELETE', `/api/admin/items/${id}`)
      refetch()
    } catch (err) {
      setActionError(err.message)
    }
  }

  async function handleRefreshPrice(id) {
    setActionError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'POST', `/api/admin/items/${id}/refresh_price`)
      dispatch({ type: 'ROW_MENU_CLOSED' })
    } catch (err) {
      setActionError(err.message)
    }
  }

  async function handleWarmCatalogCache() {
    setActionError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items/warm_catalog_cache')
    } catch (err) {
      setActionError(err.message)
    }
  }

  async function handleBulkWarmCache() {
    setActionError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items/bulk_warm_cache', {
        item_ids: [...state.selectedIds],
      })
      dispatch({ type: 'SELECTION_CLEARED' })
    } catch (err) {
      setActionError(err.message)
    }
  }

  return (
    <section className="page">
      <div className="page-head">
        <h1>Item</h1>
      </div>
      <div className="resource">
        <div className="resource-head">
          <h2>All records</h2>
          <div className="resource-head-right">
            <button
              type="button"
              className="btn ghost-cache"
              title="ItemCatalogCache — catalog list/filter cache, not tied to specific Items"
              onClick={handleWarmCatalogCache}
            >
              Warm catalog cache
            </button>
            <span className="toolbar-divider" />
            <span className="sel-count">
              {state.selectedIds.size > 0 ? `Selected: ${state.selectedIds.size}` : ''}
            </span>
            <button
              type="button"
              className="btn ghost-cache"
              disabled={state.selectedIds.size === 0}
              onClick={handleBulkWarmCache}
            >
              Warm cache
            </button>
            <button
              type="button"
              className="btn primary"
              onClick={() => dispatch({ type: 'CREATE_PANEL_TOGGLED' })}
            >
              + New Item
            </button>
          </div>
        </div>

        {actionError && (
          <p className="admin-login-error resource-error" role="alert">
            {actionError}
          </p>
        )}

        {state.isCreatePanelOpen && (
          <div className="create-panel open">
            <form onSubmit={handleCreateSubmit}>
              <div className="form-grid">
                <div className="field" style={{ gridColumn: '1/-1' }}>
                  <label htmlFor="item-create-name">Item name</label>
                  <input
                    id="item-create-name"
                    type="text"
                    placeholder="AK-47 | Redline (Field-Tested)"
                    value={createName}
                    onChange={(event) => setCreateName(event.target.value)}
                  />
                </div>
              </div>
              {createError && <p className="admin-login-error">{createError}</p>}
              <p className="form-hint">
                The remaining data (category, condition, price, icon) will be fetched from Steam
                automatically.
              </p>
              <div className="form-actions">
                <button
                  type="button"
                  className="btn"
                  onClick={() => dispatch({ type: 'CREATE_PANEL_CLOSED' })}
                >
                  Cancel
                </button>
                <button type="submit" className="btn primary">
                  Add
                </button>
              </div>
            </form>
          </div>
        )}

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
                      dispatch({ type: 'ALL_TOGGLED', checked: event.target.checked, ids: allIds })
                    }
                  />
                </th>
                <th>market_hash_name</th>
                <th>Category</th>
                <th>Price</th>
                <th>24h, %</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {items.map((item) => {
                const metadata = item.metadata || {}
                const pct = changePercent(item.current_price_cents, item.change_24h_cents)
                const direction = trendDirection(pct)
                return (
                  <tr key={item.id}>
                    <td className="col-check">
                      <input
                        type="checkbox"
                        className="row-check"
                        aria-label={`Select ${item.market_hash_name}`}
                        checked={state.selectedIds.has(item.id)}
                        onChange={() => dispatch({ type: 'ROW_TOGGLED', id: item.id })}
                      />
                    </td>
                    <td>
                      <div className="item-cell">
                        <Swatch iconUrl={metadata.icon_url} />
                        {item.market_hash_name}
                        {metadata.stattrak && <span className="st-tag">ST™</span>}
                      </div>
                    </td>
                    <td className="text-muted">{metadata.category}</td>
                    <td className="mono">{fmtPrice(item.current_price_cents)}</td>
                    <td className={`mono ${direction === 'flat' ? 'text-muted' : direction}`}>
                      {direction === 'flat'
                        ? '—'
                        : `${direction === 'up' ? '▲' : '▼'} ${Math.abs(pct).toFixed(1)}%`}
                    </td>
                    <td>
                      <div className="row-actions">
                        <div className="menu-wrap">
                          <button
                            type="button"
                            className="icon-btn"
                            onClick={() => dispatch({ type: 'ROW_MENU_TOGGLED', id: item.id })}
                          >
                            ⋯
                          </button>
                          {state.openRowMenuId === item.id && (
                            <div className="action-menu open">
                              <button type="button" onClick={() => handleRefreshPrice(item.id)}>
                                <span className="menu-icon">⟲</span>
                                Refresh price now
                              </button>
                              <div className="divider" />
                              <button
                                type="button"
                                className="danger"
                                onClick={() => handleDelete(item.id)}
                              >
                                <span className="menu-icon">✕</span>
                                Delete
                              </button>
                            </div>
                          )}
                        </div>
                      </div>
                    </td>
                  </tr>
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
