import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import * as fs from 'fs'
import * as os from 'os'
import * as path from 'path'
import { readCsv, writeCsv, createCsvTemplate } from './csv-handler'
import type { FileData } from '../protocols/types'

let dir: string

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-csv-test-'))
})

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true })
})

function writeRaw(filename: string, content: string): string {
  const p = path.join(dir, filename)
  fs.writeFileSync(p, content, 'utf-8')
  return p
}

describe('readCsv', () => {
  it('parses a minimal valid CSV with only the required columns', () => {
    const p = writeRaw(
      'min.csv',
      'Port,Type,Current_Label,New_Label,Notes\n1,INPUT,CAM 1,,\n2,OUTPUT,MON 1,NEW MON,note here\n',
    )
    const data = readCsv(p)
    expect(data.ports).toHaveLength(2)
    expect(data.ports[0]).toMatchObject({ port: 1, type: 'INPUT', currentLabel: 'CAM 1', newLabel: null, notes: '' })
    expect(data.ports[1]).toMatchObject({ port: 2, type: 'OUTPUT', currentLabel: 'MON 1', newLabel: 'NEW MON', notes: 'note here' })
    expect(data.fileType).toBe('csv')
  })

  it('defaults currentLabelLine2/newLabelLine2 to empty/null when Line2 columns are absent', () => {
    const p = writeRaw('nolines.csv', 'Port,Type,Current_Label,New_Label,Notes\n1,INPUT,CAM 1,,\n')
    const data = readCsv(p)
    expect(data.ports[0].currentLabelLine2).toBe('')
    expect(data.ports[0].newLabelLine2).toBeNull()
  })

  it('parses Current_Label_Line2/New_Label_Line2 when present', () => {
    const p = writeRaw(
      'lines.csv',
      'Port,Type,Current_Label,Current_Label_Line2,New_Label,New_Label_Line2,Notes\n1,INPUT,CAM 1,Line Two,,NEW L2,\n',
    )
    const data = readCsv(p)
    expect(data.ports[0].currentLabelLine2).toBe('Line Two')
    expect(data.ports[0].newLabelLine2).toBe('NEW L2')
  })

  it('defaults currentColor to 4 (Blue) when Current_Color column is absent', () => {
    const p = writeRaw('nocolor.csv', 'Port,Type,Current_Label,New_Label,Notes\n1,INPUT,CAM 1,,\n')
    const data = readCsv(p)
    expect(data.ports[0].currentColor).toBe(4)
    expect(data.ports[0].newColor).toBeNull()
  })

  it('parses Current_Color/New_Color when present and in range', () => {
    const p = writeRaw(
      'color.csv',
      'Port,Type,Current_Label,New_Label,Current_Color,New_Color,Notes\n1,INPUT,CAM 1,,7,2,\n',
    )
    const data = readCsv(p)
    expect(data.ports[0].currentColor).toBe(7)
    expect(data.ports[0].newColor).toBe(2)
  })

  it('clamps an out-of-range Current_Color to the default (4)', () => {
    const p = writeRaw(
      'badcolor.csv',
      'Port,Type,Current_Label,New_Label,Current_Color,New_Color,Notes\n1,INPUT,CAM 1,,99,,\n',
    )
    const data = readCsv(p)
    expect(data.ports[0].currentColor).toBe(4)
  })

  it('treats an out-of-range New_Color as null rather than clamping', () => {
    const p = writeRaw(
      'badnewcolor.csv',
      'Port,Type,Current_Label,New_Label,Current_Color,New_Color,Notes\n1,INPUT,CAM 1,,4,0,\n',
    )
    const data = readCsv(p)
    expect(data.ports[0].newColor).toBeNull()
  })

  it('throws when a required column is missing', () => {
    const p = writeRaw('missing.csv', 'Port,Type,Current_Label,Notes\n1,INPUT,CAM 1,\n')
    expect(() => readCsv(p)).toThrow(/missing required columns/i)
    expect(() => readCsv(p)).toThrow(/New_Label/)
  })

  it('throws on a non-numeric port number', () => {
    const p = writeRaw('badport.csv', 'Port,Type,Current_Label,New_Label,Notes\nABC,INPUT,CAM 1,,\n')
    expect(() => readCsv(p)).toThrow(/Invalid port number/)
  })

  it('throws on an invalid Type value', () => {
    const p = writeRaw('badtype.csv', 'Port,Type,Current_Label,New_Label,Notes\n1,BOGUS,CAM 1,,\n')
    expect(() => readCsv(p)).toThrow(/Invalid type/)
  })

  it('uppercases and trims a lowercase/whitespace-padded Type value', () => {
    const p = writeRaw('lowertype.csv', 'Port,Type,Current_Label,New_Label,Notes\n1, input ,CAM 1,,\n')
    const data = readCsv(p)
    expect(data.ports[0].type).toBe('INPUT')
  })

  it('treats a blank New_Label cell as null (not empty string)', () => {
    const p = writeRaw('blanknew.csv', 'Port,Type,Current_Label,New_Label,Notes\n1,INPUT,CAM 1,,\n')
    const data = readCsv(p)
    expect(data.ports[0].newLabel).toBeNull()
  })
})

describe('writeCsv / round-trip', () => {
  it('round-trips ports through write then read', () => {
    const data: FileData = {
      ports: [
        {
          port: 1,
          type: 'INPUT',
          currentLabel: 'CAM 1',
          newLabel: 'NEW CAM',
          currentLabelLine2: 'L2',
          newLabelLine2: null,
          currentColor: 3,
          newColor: 7,
          notes: 'test note',
        },
      ],
    }
    const p = path.join(dir, 'roundtrip.csv')
    writeCsv(p, data)
    const reread = readCsv(p)
    expect(reread.ports[0]).toMatchObject({
      port: 1,
      type: 'INPUT',
      currentLabel: 'CAM 1',
      newLabel: 'NEW CAM',
      currentLabelLine2: 'L2',
      newLabelLine2: null,
      currentColor: 3,
      newColor: 7,
      notes: 'test note',
    })
  })

  it('writes commas and quotes inside labels safely (CSV quoting)', () => {
    const data: FileData = {
      ports: [
        {
          port: 1,
          type: 'INPUT',
          currentLabel: 'CAM, "Wide"',
          newLabel: null,
          currentLabelLine2: '',
          newLabelLine2: null,
          currentColor: 4,
          newColor: null,
          notes: '',
        },
      ],
    }
    const p = path.join(dir, 'quoting.csv')
    writeCsv(p, data)
    const reread = readCsv(p)
    expect(reread.ports[0].currentLabel).toBe('CAM, "Wide"')
  })
})

describe('createCsvTemplate', () => {
  it('creates 2x the requested port count (inputs + outputs)', () => {
    const p = path.join(dir, 'template.csv')
    createCsvTemplate(p, 4)
    const data = readCsv(p)
    expect(data.ports).toHaveLength(8)
    expect(data.ports.filter((x) => x.type === 'INPUT')).toHaveLength(4)
    expect(data.ports.filter((x) => x.type === 'OUTPUT')).toHaveLength(4)
  })

  it('defaults to 32 ports when no count is given', () => {
    const p = path.join(dir, 'template32.csv')
    createCsvTemplate(p)
    const data = readCsv(p)
    expect(data.ports).toHaveLength(64)
  })
})
