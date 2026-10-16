const SORT_OPTIONS = ['value_desc', 'value_asc', 'items_desc', 'items_asc']
const SORT_LABELS = {
  value_desc: 'Value, high to low',
  value_asc: 'Value, low to high',
  items_desc: 'Items, high to low',
  items_asc: 'Items, low to high',
}

export function InventorySortDropdown({ isOpen, onToggle, sort, onSortChange }) {
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
