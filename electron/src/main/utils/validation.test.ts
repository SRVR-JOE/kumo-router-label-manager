import { describe, it, expect } from 'vitest'
import {
  PORT_NUMBER_MAX,
  COLOR_ID_MIN,
  COLOR_ID_MAX,
  MAX_LABEL_LENGTH,
  validateIpAddress,
  validatePortNumber,
  validateColorId,
  sanitizeLabel,
} from './validation'

describe('constants', () => {
  it('exposes expected boundary constants', () => {
    expect(PORT_NUMBER_MAX).toBe(120)
    expect(COLOR_ID_MIN).toBe(1)
    expect(COLOR_ID_MAX).toBe(9)
    expect(MAX_LABEL_LENGTH).toBe(255)
  })
})

describe('validateIpAddress', () => {
  it('accepts a plain valid IPv4 address', () => {
    expect(validateIpAddress('192.168.100.52')).toBe(true)
  })

  it('accepts boundary octet values 0 and 255', () => {
    expect(validateIpAddress('0.0.0.0')).toBe(true)
    expect(validateIpAddress('255.255.255.255')).toBe(true)
  })

  it('rejects an octet above 255', () => {
    expect(validateIpAddress('192.168.100.256')).toBe(false)
  })

  it('rejects negative-looking octets', () => {
    expect(validateIpAddress('192.168.100.-1')).toBe(false)
  })

  it('rejects too few segments', () => {
    expect(validateIpAddress('192.168.100')).toBe(false)
  })

  it('rejects too many segments', () => {
    expect(validateIpAddress('192.168.100.52.1')).toBe(false)
  })

  it('rejects non-numeric segments', () => {
    expect(validateIpAddress('192.168.abc.1')).toBe(false)
  })

  it('rejects segments with leading zeros (strict round-trip check)', () => {
    // parseInt('01') === 1, but String(1) !== '01' so this must fail
    expect(validateIpAddress('192.168.01.1')).toBe(false)
  })

  it('rejects empty string', () => {
    expect(validateIpAddress('')).toBe(false)
  })

  it('rejects trailing dot', () => {
    expect(validateIpAddress('192.168.100.52.')).toBe(false)
  })
})

describe('validatePortNumber', () => {
  it('accepts 1 as the lower boundary', () => {
    expect(validatePortNumber(1)).toBe(true)
  })

  it('accepts the default max boundary (120)', () => {
    expect(validatePortNumber(120)).toBe(true)
  })

  it('rejects 0', () => {
    expect(validatePortNumber(0)).toBe(false)
  })

  it('rejects one above the default max', () => {
    expect(validatePortNumber(121)).toBe(false)
  })

  it('rejects negative numbers', () => {
    expect(validatePortNumber(-5)).toBe(false)
  })

  it('rejects non-integers', () => {
    expect(validatePortNumber(1.5)).toBe(false)
  })

  it('respects a custom max override', () => {
    expect(validatePortNumber(64, 64)).toBe(true)
    expect(validatePortNumber(65, 64)).toBe(false)
  })
})

describe('validateColorId', () => {
  it('accepts every value in the valid 1-9 range', () => {
    for (let c = 1; c <= 9; c++) {
      expect(validateColorId(c)).toBe(true)
    }
  })

  it('rejects 0', () => {
    expect(validateColorId(0)).toBe(false)
  })

  it('rejects 10', () => {
    expect(validateColorId(10)).toBe(false)
  })

  it('rejects negative values', () => {
    expect(validateColorId(-1)).toBe(false)
  })

  it('rejects non-integers', () => {
    expect(validateColorId(4.2)).toBe(false)
  })
})

describe('sanitizeLabel', () => {
  it('strips LF characters', () => {
    expect(sanitizeLabel('CAM\nB')).toBe('CAMB')
  })

  it('strips CR characters', () => {
    expect(sanitizeLabel('CAM\rB')).toBe('CAMB')
  })

  it('strips CRLF pairs entirely', () => {
    expect(sanitizeLabel('CAM\r\nB')).toBe('CAMB')
  })

  it('leaves a plain label unchanged', () => {
    expect(sanitizeLabel('CAM 1')).toBe('CAM 1')
  })

  it('truncates to the default max length', () => {
    const long = 'X'.repeat(300)
    expect(sanitizeLabel(long)).toHaveLength(255)
  })

  it('truncates to a custom max length', () => {
    expect(sanitizeLabel('ABCDEFGHIJ', 5)).toBe('ABCDE')
  })

  it('does not backslash-escape quotes (unlike the KUMO telnet label escaper)', () => {
    // sanitizeLabel is a generic helper; quote-escaping is protocol-specific
    // and lives in kumo-telnet.ts's escapeLabel, not here.
    expect(sanitizeLabel('CAM "A"')).toBe('CAM "A"')
  })

  it('handles empty string', () => {
    expect(sanitizeLabel('')).toBe('')
  })
})
