const SORT_OPTIONS = ['change_24h_desc', 'price_desc', 'price_asc', 'name_asc']

const SORT_LABELS = {
  change_24h_desc: '24h change',
  price_desc: 'Price: high to low',
  price_asc: 'Price: low to high',
  name_asc: 'Name A–Z',
}

export function SortDropdown({ isOpen, onToggle, sort, onSortChange }) {
  return (
    <div className={`dropdown${isOpen ? ' is-open' : ''}`}>
      <button type="button" className="toolbar-btn" onClick={onToggle}>
        <span>Sort: {SORT_LABELS[sort]}</span>
        <Chevron />
      </button>
      {isOpen && (
        <div className="dropdown-panel">
          {SORT_OPTIONS.map((key) => (
            <button
              key={key}
              type="button"
              className={`sort-option${key === sort ? ' is-active' : ''}`}
              onClick={() => onSortChange(key)}
            >
              {SORT_LABELS[key]}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function Chevron() {
  return (
    <svg className="chev" width="9" height="6" viewBox="0 0 9 6" aria-hidden="true">
      <path
        d="M1 1L4.5 5L8 1"
        stroke="currentColor"
        strokeWidth="1.4"
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}
