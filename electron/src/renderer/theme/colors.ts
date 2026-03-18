// KUMO color constants for use in React components

export const KUMO_COLORS: Record<number, { name: string; idle: string; active: string }> = {
  1: { name: 'Red',         idle: '#cb7676', active: '#fe0000' },
  2: { name: 'Orange',      idle: '#e6a52e', active: '#f76700' },
  3: { name: 'Yellow',      idle: '#d9cb7e', active: '#d7af00' },
  4: { name: 'Blue',        idle: '#87b4c8', active: '#009af4' },
  5: { name: 'Teal',        idle: '#64c896', active: '#00a263' },
  6: { name: 'Light Green', idle: '#ade68e', active: '#60b71f' },
  7: { name: 'Indigo',      idle: '#7888cb', active: '#3a5ef6' },
  8: { name: 'Purple',      idle: '#9b8ce1', active: '#8100f4' },
  9: { name: 'Pink',        idle: '#c84b91', active: '#f30088' },
}

export const KUMO_DEFAULT_COLOR = 4
