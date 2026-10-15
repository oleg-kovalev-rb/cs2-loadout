import { useReducer } from 'react'
import { priceLogsReducer, initialState } from './priceLogsReducer'
import { useAdminList } from '../hooks/useAdminList'
import { adminSend } from '../adminApi'
import { Pagination } from '../components/Pagination'
import { fmtPrice, fmtDateTime } from '../utils/format'

export function PriceLogsPage({ fetcherUrl, bridgeToken }) {
  const [state, dispatch] = useReducer(priceLogsReducer, initialState)
  const { data, status, refetch } = useAdminList(fetcherUrl, bridgeToken, '/api/admin/price_logs', {
    page: state.page,
    perPage: state.perPage,
  })

  if (status === 'loading' && !data) return <div className="page-placeholder">Загрузка…</div>
  if (status === 'error' && !data)
    return <div className="page-placeholder">Не удалось загрузить PriceLog</div>

  const priceLogs = data?.price_logs ?? []
  const meta = data?.meta ?? { total_count: 0, total_pages: 0 }

  async function handleDelete(log) {
    await adminSend(
      fetcherUrl,
      bridgeToken,
      'DELETE',
      `/api/admin/items/${log.item_id}/price_logs/${log.id}`,
    )
    refetch()
  }

  return (
    <section className="page">
      <div className="page-head">
        <h1>PriceLog</h1>
      </div>
      <div className="resource">
        <div className="resource-head">
          <h2>Все записи</h2>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Item</th>
                <th>Lowest</th>
                <th>Median</th>
                <th>Volume</th>
                <th>Записано</th>
                <th className="col-actions" />
              </tr>
            </thead>
            <tbody>
              {priceLogs.map((log) => (
                <tr key={log.id}>
                  <td>{log.market_hash_name}</td>
                  <td className="mono">{fmtPrice(log.lowest_price_cents)}</td>
                  <td className="mono">{fmtPrice(log.median_price_cents)}</td>
                  <td className="mono text-muted">{log.volume}</td>
                  <td className="mono text-muted">{fmtDateTime(log.created_at)}</td>
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
