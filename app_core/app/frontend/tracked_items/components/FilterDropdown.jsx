import { rarityColor } from '../utils/format'
import { activeFilterCount } from '../reducer'

export function FilterDropdown({
  isOpen,
  onToggle,
  categories,
  rarities,
  stattrakOnly,
  availableCategories,
  availableRarities,
  showStattrak,
  onCategoryToggle,
  onRarityToggle,
  onStattrakToggle,
  onClear,
}) {
  const count = activeFilterCount({ categories, rarities, stattrakOnly })

  return (
    <div className={`dropdown${isOpen ? ' is-open' : ''}`}>
      <button
        type="button"
        className={`toolbar-btn${count > 0 ? ' has-active' : ''}`}
        onClick={onToggle}
      >
        <span className="toolbar-btn-label">
          Filters
          {count > 0 && <span className="filter-badge">{count}</span>}
        </span>
        <Chevron />
      </button>
      {isOpen && (
        <div className="dropdown-panel">
          <div className="filter-group">
            <span className="filter-group-label">Category</span>
            <div className="chip-row">
              {availableCategories.map((category) => (
                <button
                  key={category}
                  type="button"
                  className={`chip${categories.has(category) ? ' is-active' : ''}`}
                  onClick={() => onCategoryToggle(category)}
                >
                  {category}
                </button>
              ))}
            </div>
          </div>
          <div className="filter-group">
            <span className="filter-group-label">Rarity</span>
            <div className="chip-row">
              {availableRarities.map((rarity) => (
                <button
                  key={rarity}
                  type="button"
                  className={`chip${rarities.has(rarity) ? ' is-active' : ''}`}
                  onClick={() => onRarityToggle(rarity)}
                >
                  <span className="dot" style={{ background: rarityColor(rarity) }} />
                  {rarity}
                </button>
              ))}
            </div>
          </div>
          {showStattrak && (
            <div className="filter-group">
              <span className="filter-group-label">Special</span>
              <div className="chip-row">
                <button
                  type="button"
                  className={`chip${stattrakOnly ? ' is-active' : ''}`}
                  onClick={onStattrakToggle}
                >
                  StatTrak&trade;
                </button>
              </div>
            </div>
          )}
          <button type="button" className="filter-clear" onClick={onClear}>
            Clear filters
          </button>
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
