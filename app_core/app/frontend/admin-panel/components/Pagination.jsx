import { buildPageNumbers } from '../utils/pagination'

export function Pagination({
  page,
  perPage,
  totalCount,
  totalPages,
  onPageChange,
  onPerPageChange,
}) {
  const start = totalCount === 0 ? 0 : (page - 1) * perPage + 1
  const end = Math.min(page * perPage, totalCount)

  return (
    <div className="pagination">
      <span>{totalCount === 0 ? 'Нет записей' : `Показано ${start}–${end} из ${totalCount}`}</span>

      {totalPages > 1 && (
        <div className="pg-controls">
          <button
            type="button"
            className="pg-btn"
            disabled={page <= 1}
            onClick={() => onPageChange(page - 1)}
          >
            ‹
          </button>
          {buildPageNumbers(page, totalPages).map((entry, index) =>
            entry === '…' ? (
              <span className="pg-ellipsis" key={`ellipsis-${index}`}>
                …
              </span>
            ) : (
              <button
                type="button"
                key={entry}
                className={`pg-btn${entry === page ? ' active' : ''}`}
                onClick={() => onPageChange(entry)}
              >
                {entry}
              </button>
            ),
          )}
          <button
            type="button"
            className="pg-btn"
            disabled={page >= totalPages}
            onClick={() => onPageChange(page + 1)}
          >
            ›
          </button>
        </div>
      )}

      <div className="pg-size">
        на странице
        <select value={perPage} onChange={(event) => onPerPageChange(Number(event.target.value))}>
          <option value={25}>25</option>
          <option value={50}>50</option>
          <option value={100}>100</option>
        </select>
      </div>
    </div>
  )
}
