import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import * as fs from 'fs'
import * as os from 'os'
import * as path from 'path'
import { readJson, writeJson } from './json-handler'
import type { FileData } from '../protocols/types'

let dir: string

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-json-test-'))
})

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true })
})

function writeRaw(filename: string, content: string): string {
  const p = path.join(dir, filename)
  fs.writeFileSync(p, content, 'utf-8')
  return p
}

describe('readJson', () => {
  it('parses a minimal valid ports array', () => {
    const p = writeRaw(
      'min.json',
      JSON.stringify({ version: '1.0', ports: [{ port: 1, type: 'INPUT', current_label: 'CAM 1' }] }),
    )
    const data = readJson(p)
    expect(data.ports).toHaveLength(1)
    expect(data.ports[0]).toMatchObject({ port: 1, type: 'INPUT', currentLabel: 'CAM 1', newLabel: null })
    expect(data.fileType).toBe('json')
  })

  it('applies defaults for optional fields (currentColor=4, notes="", etc.)', () => {
    const p = writeRaw('defaults.json', JSON.stringify({ ports: [{ port: 1, type: 'INPUT' }] }))
    const data = readJson(p)
    expect(data.ports[0]).toMatchObject({
      currentLabel: '',
      newLabel: null,
      currentLabelLine2: '',
      newLabelLine2: null,
      currentColor: 4,
      newColor: null,
      notes: '',
    })
  })

  it('preserves explicit current_color/new_color values', () => {
    const p = writeRaw(
      'colors.json',
      JSON.stringify({ ports: [{ port: 1, type: 'OUTPUT', current_label: 'MON', current_color: 8, new_color: 2 }] }),
    )
    const data = readJson(p)
    expect(data.ports[0].currentColor).toBe(8)
    expect(data.ports[0].newColor).toBe(2)
  })

  it('uppercases a lowercase type field', () => {
    const p = writeRaw('lowertype.json', JSON.stringify({ ports: [{ port: 1, type: 'input', current_label: 'CAM' }] }))
    const data = readJson(p)
    expect(data.ports[0].type).toBe('INPUT')
  })

  it('defaults to INPUT type when type is omitted', () => {
    const p = writeRaw('notype.json', JSON.stringify({ ports: [{ port: 1, current_label: 'CAM' }] }))
    const data = readJson(p)
    expect(data.ports[0].type).toBe('INPUT')
  })

  it('throws on invalid JSON syntax', () => {
    const p = writeRaw('invalid.json', '{ this is not json')
    expect(() => readJson(p)).toThrow(/Invalid JSON/)
  })

  it('throws when the "ports" array is missing', () => {
    const p = writeRaw('noports.json', JSON.stringify({ version: '1.0' }))
    expect(() => readJson(p)).toThrow(/missing "ports" array/)
  })

  it('throws when "ports" is present but not an array', () => {
    const p = writeRaw('badports.json', JSON.stringify({ ports: 'not-an-array' }))
    expect(() => readJson(p)).toThrow(/missing "ports" array/)
  })

  it('throws on a non-numeric or zero/negative port number', () => {
    const p1 = writeRaw('badport1.json', JSON.stringify({ ports: [{ port: 'x', type: 'INPUT' }] }))
    expect(() => readJson(p1)).toThrow(/Invalid port number/)

    const p2 = writeRaw('badport2.json', JSON.stringify({ ports: [{ port: 0, type: 'INPUT' }] }))
    expect(() => readJson(p2)).toThrow(/Invalid port number/)
  })

  it('throws on an invalid type string', () => {
    const p = writeRaw('badtype.json', JSON.stringify({ ports: [{ port: 1, type: 'BOGUS' }] }))
    expect(() => readJson(p)).toThrow(/Invalid type/)
  })
})

describe('writeJson / round-trip', () => {
  it('round-trips a full port entry through write then read', () => {
    const data: FileData = {
      ports: [
        {
          port: 5,
          type: 'OUTPUT',
          currentLabel: 'MON A',
          newLabel: 'MON B',
          currentLabelLine2: 'L2',
          newLabelLine2: 'NEW L2',
          currentColor: 6,
          newColor: 1,
          notes: 'some notes',
        },
      ],
    }
    const p = path.join(dir, 'roundtrip.json')
    writeJson(p, data)
    const reread = readJson(p)
    expect(reread.ports[0]).toMatchObject({
      port: 5,
      type: 'OUTPUT',
      currentLabel: 'MON A',
      newLabel: 'MON B',
      currentLabelLine2: 'L2',
      newLabelLine2: 'NEW L2',
      currentColor: 6,
      newColor: 1,
      notes: 'some notes',
    })
  })

  it('writes a version field and valid JSON', () => {
    const p = path.join(dir, 'version.json')
    writeJson(p, { ports: [] })
    const raw = JSON.parse(fs.readFileSync(p, 'utf-8'))
    expect(raw.version).toBe('1.0')
    expect(raw.ports).toEqual([])
  })

  it('preserves unicode and special characters through the round-trip', () => {
    const data: FileData = {
      ports: [
        {
          port: 1,
          type: 'INPUT',
          currentLabel: 'CAM "1" – Ünïcode',
          newLabel: null,
          currentLabelLine2: '',
          newLabelLine2: null,
          currentColor: 4,
          newColor: null,
          notes: '',
        },
      ],
    }
    const p = path.join(dir, 'unicode.json')
    writeJson(p, data)
    const reread = readJson(p)
    expect(reread.ports[0].currentLabel).toBe('CAM "1" – Ünïcode')
  })
})
