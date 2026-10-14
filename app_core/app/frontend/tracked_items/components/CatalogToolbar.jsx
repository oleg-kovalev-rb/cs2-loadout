import { useEffect, useRef } from 'react'
import { FilterDropdown } from './FilterDropdown'
import { SortDropdown } from './SortDropdown'
import { ViewToggle } from './ViewToggle'

export function CatalogToolbar({
  search,
  onSearchChange,
  openDropdown,
  onDropdownToggle,
  onDropdownsClosed,
  categories,
  rarities,
  stattrakOnly,
  availableCategories,
  availableRarities,
  showStattrak,
  onCategoryToggle,
  onRarityToggle,
  onStattrakToggle,
  onFiltersClear,
  sort,
  onSortChange,
  view,
  onViewChange,
}) {
  const toolbarRef = useRef(null)

  useEffect(() => {
    function handleOutsideClick(event) {
      if (toolbarRef.current && !toolbarRef.current.contains(event.target)) {
        onDropdownsClosed()
      }
    }
    function handleEscape(event) {
      if (event.key === 'Escape') onDropdownsClosed()
    }

    document.addEventListener('click', handleOutsideClick)
    document.addEventListener('keydown', handleEscape)
    return () => {
      document.removeEventListener('click', handleOutsideClick)
      document.removeEventListener('keydown', handleEscape)
    }
  }, [onDropdownsClosed])

  return (
    <div className="catalog-toolbar" ref={toolbarRef}>
      <div className="search-field">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <circle cx="7" cy="7" r="5.2" stroke="currentColor" strokeWidth="1.4" />
          <path d="M11 11L14.2 14.2" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
        <input
          className="search-input"
          type="text"
          placeholder="Search by weapon, skin, or collection…"
          autoComplete="off"
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
        />
      </div>

      <FilterDropdown
        isOpen={openDropdown === 'filter'}
        onToggle={() => onDropdownToggle('filter')}
        categories={categories}
        rarities={rarities}
        stattrakOnly={stattrakOnly}
        availableCategories={availableCategories}
        availableRarities={availableRarities}
        showStattrak={showStattrak}
        onCategoryToggle={onCategoryToggle}
        onRarityToggle={onRarityToggle}
        onStattrakToggle={onStattrakToggle}
        onClear={onFiltersClear}
      />

      <SortDropdown isOpen={openDropdown === 'sort'} onToggle={() => onDropdownToggle('sort')} sort={sort} onSortChange={onSortChange} />

      <ViewToggle view={view} onChange={onViewChange} />
    </div>
  )
}
