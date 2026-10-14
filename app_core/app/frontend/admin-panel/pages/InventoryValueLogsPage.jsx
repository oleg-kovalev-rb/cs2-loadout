import { useReducer } from 'react'
import { inventoryValueLogsReducer, initialState } from './inventoryValueLogsReducer'
import { useAdminList } from '../hooks/useAdminList'
import { adminSend } from '../adminApi'
import { Pagination } from '../components/Pagination'
import { fmtPrice, fmtDate } from '../utils/format'

export function InventoryValueLogsPage({ fetcherUrl, bridgeToken }) {
  const [state, dispatch] = useReducer(inventoryValueLogsReducer, initialState)
  const { data, status, refetch } = useAdminList(fetcherUrl, bridgeToken, '/api/admin/inventory_value_logs', {
    page: state.page,
    perPage: state.perPage,
  })

  if (status === 'loading' && !data) return <div className="page-placeholder">Загрузка…</div>
  if (status === 'error' && !data) return <div className="page-placeholder">Не удалось загрузить InventoryValueLog</div>

  const logs = data?.inventory_value_logs ?? []
  const meta = data?.meta ?? { total_count: 0, total_pages: 0 }

  async function handleDelete(log) {
    await adminSend(
      fetcherUrl,
      bridgeToken,
      'DELETE',
      `/api/admin/user_inventories/${log.steam_id}/inventory_value_logs/${log.id}`
    )
    refetch()
  }

  return (
    <section className="page">
      <div className="page-head">
        <h1>InventoryValueLog</h1>
      </div>
      <div className="resource">
        <div className="resource-head">
          <h2>Все записи</h2>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Steam ID</th>
                <th>Дата</th>
                <th>Стоимость</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {logs.map((log) => (
                <tr key={log.id}>
                  <td className="mono">{log.steam_id}</td>
                  <td className="mono text-muted">{fmtDate(log.log_date)}</td>
                  <td className="mono">{fmtPrice(log.total_value_cents)}</td>
                  <td>
                    <div className="row-actions">
                      <button
                        type="button"
                        className="icon-btn danger"
                        aria-label={`Удалить запись ${log.id}`}
                        onClick={() => handleDelete(log)}
                      >
                        ✕
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
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
