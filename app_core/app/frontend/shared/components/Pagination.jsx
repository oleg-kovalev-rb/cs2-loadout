export function Pagination({ page, totalPages, totalCount, pageSize, onPrev, onNext }) {
  const start = totalCount === 0 ? 0 : page * pageSize + 1
  const end = Math.min(page * pageSize + pageSize, totalCount)

  return (
    <div className="list-pager">
      <span className="pager-range tabular">{totalCount === 0 ? '0 of 0' : `${start}–${end} of ${totalCount}`}</span>
      <div className="pager-btns">
        <button type="button" className="pager-btn" onClick={onPrev} disabled={page === 0} aria-label="Previous page">
          ‹
        </button>
        <span className="pager-page tabular">{page + 1} / {totalPages}</span>
        <button type="button" className="pager-btn" onClick={onNext} disabled={page >= totalPages - 1} aria-label="Next page">
          ›
        </button>
      </div>
    </div>
  )
}
