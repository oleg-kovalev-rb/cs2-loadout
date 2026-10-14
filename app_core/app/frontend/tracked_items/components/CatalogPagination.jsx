const PER_PAGE_OPTIONS = [25, 50, 100]

export function CatalogPagination({ page, totalPages, totalCount, perPage, onPrev, onNext, onPerPageChange }) {
  const start = totalCount === 0 ? 0 : (page - 1) * perPage + 1
  const end = Math.min(page * perPage, totalCount)

  return (
    <div className="list-pager">
      <span className="pager-range tabular">
        {totalCount === 0 ? '0 of 0' : `${start}–${end} of ${totalCount.toLocaleString('en-US')}`}
      </span>
      <div className="pager-right">
        <label className="per-page-field">
          <span>Per page</span>
          <select
            className="per-page-select"
            value={perPage}
            onChange={(event) => onPerPageChange(Number(event.target.value))}
          >
            {PER_PAGE_OPTIONS.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
        <div className="pager-btns">
          <button type="button" className="pager-btn" onClick={onPrev} disabled={page <= 1} aria-label="Previous page">
            &lsaquo;
          </button>
          <span className="pager-page tabular">
            {page} / {Math.max(totalPages, 1)}
          </span>
          <button
            type="button"
            className="pager-btn"
            onClick={onNext}
            disabled={page >= totalPages}
            aria-label="Next page"
          >
            &rsaquo;
          </button>
        </div>
      </div>
    </div>
  )
}
