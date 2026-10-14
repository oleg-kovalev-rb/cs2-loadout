import { renderHook, act } from '@testing-library/react'
import { describe, test, expect, afterEach } from 'vitest'
import { useHashRoute } from '../useHashRoute'

afterEach(() => {
  window.location.hash = ''
})

describe('useHashRoute', () => {
  test('defaults to item when there is no hash', () => {
    const { result } = renderHook(() => useHashRoute())

    expect(result.current).toBe('item')
  })

  test('reads the initial hash', () => {
    window.location.hash = '#price-log'

    const { result } = renderHook(() => useHashRoute())

    expect(result.current).toBe('price-log')
  })

  test('updates when the hash changes', () => {
    const { result } = renderHook(() => useHashRoute())

    act(() => {
      window.location.hash = '#user-inventory'
      window.dispatchEvent(new HashChangeEvent('hashchange'))
    })

    expect(result.current).toBe('user-inventory')
  })

  test('falls back to item for an empty hash after navigating back', () => {
    window.location.hash = '#item'
    const { result } = renderHook(() => useHashRoute())

    act(() => {
      window.location.hash = ''
      window.dispatchEvent(new HashChangeEvent('hashchange'))
    })

    expect(result.current).toBe('item')
  })
})
