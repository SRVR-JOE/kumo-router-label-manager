import { describe, it, expect } from 'vitest'
import { KUMO_COLORS, KUMO_DEFAULT_COLOR, KUMO_COLOR_NAMES, DEFAULT_SETTINGS } from './types'

describe('KUMO_COLORS', () => {
  it('has exactly 9 entries', () => {
    expect(Object.keys(KUMO_COLORS)).toHaveLength(9)
  })

  it('has ids 1 through 9', () => {
    expect(Object.keys(KUMO_COLORS).map(Number).sort((a, b) => a - b)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9])
  })

  it('defaults to Blue at id 4', () => {
    expect(KUMO_DEFAULT_COLOR).toBe(4)
    expect(KUMO_COLORS[4].name).toBe('Blue')
  })

  it('every entry has a name and two well-formed hex colors', () => {
    for (const [, entry] of Object.entries(KUMO_COLORS)) {
      expect(entry.name.length).toBeGreaterThan(0)
      expect(entry.idle).toMatch(/^#[0-9a-fA-F]{6}$/)
      expect(entry.active).toMatch(/^#[0-9a-fA-F]{6}$/)
    }
  })

  it('KUMO_COLOR_NAMES stays in sync with KUMO_COLORS names', () => {
    for (const [id, entry] of Object.entries(KUMO_COLORS)) {
      expect(KUMO_COLOR_NAMES[Number(id)]).toBe(entry.name)
    }
  })
})

describe('DEFAULT_SETTINGS', () => {
  it('ships with a sane default IP and empty saved routers', () => {
    expect(DEFAULT_SETTINGS.defaultIp).toBe('192.168.100.52')
    expect(DEFAULT_SETTINGS.savedRouters).toEqual([])
    expect(DEFAULT_SETTINGS.maxLabelLength).toBe(255)
  })
})
