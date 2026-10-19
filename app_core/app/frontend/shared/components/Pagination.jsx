export function Pagination({ page, totalPages, totalCount, pageSize, onPrev, onNext }) {
  const pageCount = Math.max(totalPages, 1)
  const start = totalCount === 0 ? 0 : (page - 1) * pageSize + 1
  const end = Math.min(page * pageSize, totalCount)

  return (
    <div className="list-pager">
      <span className="pager-range tabular">
        {totalCount === 0 ? '0 of 0' : `${start}–${end} of ${totalCount}`}
      </span>
      <div className="pager-btns">
        <button
          type="button"
          className="pager-btn"
          onClick={onPrev}
          disabled={page <= 1}
          aria-label="Previous page"
        >
          ‹
        </button>
        <span className="pager-page tabular">
          {page} / {pageCount}
        </span>
        <button
          type="button"
          className="pager-btn"
          onClick={onNext}
          disabled={page >= pageCount}
          aria-label="Next page"
        >
          ›
        </button>
      </div>
    </div>
  )
}
