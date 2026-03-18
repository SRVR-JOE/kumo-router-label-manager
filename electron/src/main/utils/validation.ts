// Validation utilities

export const PORT_NUMBER_MAX = 120
export const COLOR_ID_MIN = 1
export const COLOR_ID_MAX = 9
export const MAX_LABEL_LENGTH = 255

export function validateIpAddress(ip: string): boolean {
  const parts = ip.split('.')
  if (parts.length !== 4) return false
  return parts.every(part => {
    const num = parseInt(part, 10)
    return !isNaN(num) && num >= 0 && num <= 255 && String(num) === part
  })
}

export function validatePortNumber(port: number, max = PORT_NUMBER_MAX): boolean {
  return Number.isInteger(port) && port >= 1 && port <= max
}

export function validateColorId(colorId: number): boolean {
  return Number.isInteger(colorId) && colorId >= COLOR_ID_MIN && colorId <= COLOR_ID_MAX
}

export function sanitizeLabel(label: string, maxLength = MAX_LABEL_LENGTH): string {
  return label.replace(/[\r\n]/g, '').slice(0, maxLength)
}
