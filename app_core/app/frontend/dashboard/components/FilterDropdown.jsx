import { conditionAbbr } from '../utils/format'
import { activeFilterCount } from '../reducer'

export function FilterDropdown({ isOpen, onToggle, filters, weaponTypes, conditions, showStattrak, onWeaponToggle, onConditionToggle, onStattrakToggle, onClear }) {
  const count = activeFilterCount(filters)

  return (
    <div className={`dropdown${isOpen ? ' is-open' : ''}`}>
      <button type="button" className={`toolbar-btn${count > 0 ? ' has-active' : ''}`} onClick={onToggle}>
        <span>Filters</span>
        {count > 0 && <span className="filter-badge">{count}</span>}
        <Chevron />
      </button>
      {isOpen && (
        <div className="dropdown-panel">
          <div className="filter-group">
            <span className="filter-group-label">Weapon</span>
            <div className="chip-row">
              {weaponTypes.map((weapon) => (
                <button
                  key={weapon}
                  type="button"
                  className={`chip${filters.weapons.has(weapon) ? ' is-active' : ''}`}
                  onClick={() => onWeaponToggle(weapon)}
                >
                  {weapon}
                </button>
              ))}
            </div>
          </div>
          <div className="filter-group">
            <span className="filter-group-label">Condition</span>
            <div className="chip-row">
              {conditions.map((condition) => (
                <button
                  key={condition}
                  type="button"
                  className={`chip${filters.conditions.has(condition) ? ' is-active' : ''}`}
                  onClick={() => onConditionToggle(condition)}
                >
                  {conditionAbbr(condition)}
                </button>
              ))}
            </div>
          </div>
          {showStattrak && (
            <div className="filter-group">
              <span className="filter-group-label">Special</span>
              <div className="chip-row">
                <button type="button" className={`chip${filters.stattrakOnly ? ' is-active' : ''}`} onClick={onStattrakToggle}>
                  StatTrak™
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
      <path d="M1 1L4.5 5L8 1" stroke="currentColor" strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
