import { useEffect, useReducer, useState } from 'react'
import { itemsReducer, initialState } from './itemsReducer'
import { useAdminList } from '../hooks/useAdminList'
import { adminSend } from '../adminApi'
import { Pagination } from '../components/Pagination'
import { fmtPrice } from '../utils/format'

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

  if (status === 'loading' && !data) return <div className="page-placeholder">Загрузка…</div>
  if (status === 'error' && !data) return <div className="page-placeholder">Не удалось загрузить Item</div>

  const items = data?.items ?? []
  const meta = data?.meta ?? { total_count: 0, total_pages: 0 }
  const allIds = items.map((item) => item.id)
  const allSelected = allIds.length > 0 && allIds.every((id) => state.selectedIds.has(id))

  async function handleCreateSubmit(event) {
    event.preventDefault()
    setCreateError(null)
    try {
      await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items', { item: { market_hash_name: createName } })
      setCreateName('')
      dispatch({ type: 'CREATE_PANEL_CLOSED' })
      refetch()
    } catch (err) {
      setCreateError(err.message)
    }
  }

  async function handleDelete(id) {
    await adminSend(fetcherUrl, bridgeToken, 'DELETE', `/api/admin/items/${id}`)
    refetch()
  }

  async function handleRefreshPrice(id) {
    await adminSend(fetcherUrl, bridgeToken, 'POST', `/api/admin/items/${id}/refresh_price`)
    dispatch({ type: 'ROW_MENU_CLOSED' })
  }

  async function handleWarmCatalogCache() {
    await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items/warm_catalog_cache')
  }

  async function handleBulkWarmCache() {
    await adminSend(fetcherUrl, bridgeToken, 'POST', '/api/admin/items/bulk_warm_cache', {
      item_ids: [...state.selectedIds],
    })
    dispatch({ type: 'SELECTION_CLEARED' })
  }

  return (
    <section className="page">
      <div className="page-head">
        <h1>Item</h1>
      </div>
      <div className="resource">
        <div className="resource-head">
          <h2>Все записи</h2>
          <div className="resource-head-right">
            <button
              type="button"
              className="btn ghost-cache"
              title="ItemCatalogCache — кэш списков/фильтров каталога, не привязан к конкретным Item"
              onClick={handleWarmCatalogCache}
            >
              Пересоздать кэш каталога
            </button>
            <span className="toolbar-divider" />
            <span className="sel-count">{state.selectedIds.size > 0 ? `Выбрано: ${state.selectedIds.size}` : ''}</span>
            <button
              type="button"
              className="btn ghost-cache"
              disabled={state.selectedIds.size === 0}
              onClick={handleBulkWarmCache}
            >
              Пересоздать кэш
            </button>
            <button type="button" className="btn primary" onClick={() => dispatch({ type: 'CREATE_PANEL_TOGGLED' })}>
              + Новый Item
            </button>
          </div>
        </div>

        {state.isCreatePanelOpen && (
          <div className="create-panel open">
            <form onSubmit={handleCreateSubmit}>
              <div className="form-grid">
                <div className="field" style={{ gridColumn: '1/-1' }}>
                  <label htmlFor="item-create-name">Название предмета</label>
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
                Остальные данные (категория, состояние, цена, иконка) подтянутся из Steam автоматически.
              </p>
              <div className="form-actions">
                <button type="button" className="btn" onClick={() => dispatch({ type: 'CREATE_PANEL_CLOSED' })}>
                  Отмена
                </button>
                <button type="submit" className="btn primary">
                  Добавить
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
                    aria-label="Выбрать все"
                    checked={allSelected}
                    onChange={(event) => dispatch({ type: 'ALL_TOGGLED', checked: event.target.checked, ids: allIds })}
                  />
                </th>
                <th>market_hash_name</th>
                <th>Категория</th>
                <th>Цена</th>
                <th>24ч</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {items.map((item) => {
                const metadata = item.metadata || {}
                const changeUp = (item.change_24h_cents || 0) >= 0
                return (
                  <tr key={item.id}>
                    <td className="col-check">
                      <input
                        type="checkbox"
                        className="row-check"
                        aria-label={`Выбрать ${item.market_hash_name}`}
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
                    <td className={`mono ${changeUp ? 'up' : 'down'}`}>
                      {changeUp ? '▲' : '▼'} {Math.abs(item.change_24h_cents || 0)}
                    </td>
                    <td>
                      <div className="row-actions">
                        <button type="button" className="icon-btn" aria-label={`Редактировать ${item.market_hash_name}`}>
                          ✎
                        </button>
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
                                Обновить цену сейчас
                              </button>
                              <div className="divider" />
                              <button type="button" className="danger" onClick={() => handleDelete(item.id)}>
                                <span className="menu-icon">✕</span>
                                Удалить
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
