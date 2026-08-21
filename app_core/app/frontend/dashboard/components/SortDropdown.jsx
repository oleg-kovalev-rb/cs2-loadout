import { SORT_LABELS } from '../utils/filters'

const SORT_OPTIONS = [
  { key: 'delta_desc', label: '24H Δ — high to low' },
  { key: 'delta_asc', label: '24H Δ — low to high' },
  { key: 'price_desc', label: 'Price — high to low' },
  { key: 'price_asc', label: 'Price — low to high' },
  { key: 'name_asc', label: 'Name — A to Z' },
]

export function SortDropdown({ isOpen, onToggle, sort, onSortChange }) {
  return (
    <div className={`dropdown${isOpen ? ' is-open' : ''}`}>
      <button type="button" className="toolbar-btn" onClick={onToggle}>
        <span>{SORT_LABELS[sort]}</span>
        <Chevron />
      </button>
      {isOpen && (
        <div className="dropdown-panel">
          {SORT_OPTIONS.map((option) => (
            <button
              key={option.key}
              type="button"
              className={`sort-option${option.key === sort ? ' is-active' : ''}`}
              onClick={() => onSortChange(option.key)}
            >
              {option.label}
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
      <path d="M1 1L4.5 5L8 1" stroke="currentColor" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
