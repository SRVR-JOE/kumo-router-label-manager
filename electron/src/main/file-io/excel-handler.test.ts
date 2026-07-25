import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import * as fs from 'fs'
import * as os from 'os'
import * as path from 'path'
import ExcelJS from 'exceljs'
import { readExcel, writeExcel, createExcelTemplate } from './excel-handler'
import type { FileData } from '../protocols/types'

let dir: string

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-xlsx-test-'))
})

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true })
})

describe('writeExcel / readExcel round-trip', () => {
  it('round-trips a full port entry', async () => {
    const data: FileData = {
      ports: [
        {
          port: 1,
          type: 'INPUT',
          currentLabel: 'CAM 1',
          newLabel: 'NEW CAM',
          currentLabelLine2: 'L2 text',
          newLabelLine2: null,
          currentColor: 5,
          newColor: 9,
          notes: 'a note',
        },
      ],
    }
    const p = path.join(dir, 'roundtrip.xlsx')
    await writeExcel(p, data)
    const reread = await readExcel(p)
    expect(reread.ports[0]).toMatchObject({
      port: 1,
      type: 'INPUT',
      currentLabel: 'CAM 1',
      newLabel: 'NEW CAM',
      currentLabelLine2: 'L2 text',
      newLabelLine2: null,
      currentColor: 5,
      newColor: 9,
      notes: 'a note',
    })
  })

  it('writes to the expected worksheet name and header row', async () => {
    const p = path.join(dir, 'headers.xlsx')
    await writeExcel(p, { ports: [] })
    const wb = new ExcelJS.Workbook()
    await wb.xlsx.readFile(p)
    const ws = wb.getWorksheet('KUMO_Labels')
    expect(ws).toBeDefined()
    const headerValues = ws!.getRow(1).values as unknown[]
    // ExcelJS rows are 1-indexed with index 0 unused
    expect(headerValues.slice(1)).toEqual([
      'Port', 'Type', 'Current_Label', 'Current_Label_Line2', 'New_Label', 'New_Label_Line2', 'Current_Color', 'New_Color', 'Notes',
    ])
  })

  it('normalizes an empty New_Label cell to null on read', async () => {
    const p = path.join(dir, 'empty-new.xlsx')
    await writeExcel(p, {
      ports: [
        {
          port: 1, type: 'INPUT', currentLabel: 'CAM', newLabel: null,
          currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '',
        },
      ],
    })
    const reread = await readExcel(p)
    expect(reread.ports[0].newLabel).toBeNull()
  })

  it('clamps an out-of-range Current_Color read back from the sheet to the default', async () => {
    const p = path.join(dir, 'badcolor.xlsx')
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('KUMO_Labels')
    ws.addRow(['Port', 'Type', 'Current_Label', 'Current_Label_Line2', 'New_Label', 'New_Label_Line2', 'Current_Color', 'New_Color', 'Notes'])
    ws.addRow([1, 'INPUT', 'CAM', '', '', '', 99, '', ''])
    await wb.xlsx.writeFile(p)

    const reread = await readExcel(p)
    expect(reread.ports[0].currentColor).toBe(4)
  })

  it('throws a descriptive error when the expected worksheet is missing', async () => {
    const p = path.join(dir, 'wrongsheet.xlsx')
    const wb = new ExcelJS.Workbook()
    wb.addWorksheet('SomeOtherSheet')
    await wb.xlsx.writeFile(p)

    await expect(readExcel(p)).rejects.toThrow(/Worksheet 'KUMO_Labels' not found/)
  })

  it('handles a legacy sheet with no Line2/Color columns (4-column basic layout)', async () => {
    const p = path.join(dir, 'basic.xlsx')
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('KUMO_Labels')
    ws.addRow(['Port', 'Type', 'Current_Label', 'New_Label'])
    ws.addRow([1, 'INPUT', 'CAM 1', 'NEW CAM'])
    await wb.xlsx.writeFile(p)

    const reread = await readExcel(p)
    expect(reread.ports[0]).toMatchObject({
      port: 1,
      type: 'INPUT',
      currentLabel: 'CAM 1',
      newLabel: 'NEW CAM',
      currentLabelLine2: '',
      currentColor: 4,
      newColor: null,
    })
  })
})

describe('createExcelTemplate', () => {
  it('creates 2x the requested port count with blank labels', async () => {
    const p = path.join(dir, 'template.xlsx')
    await createExcelTemplate(p, 4)
    const data = await readExcel(p)
    expect(data.ports).toHaveLength(8)
    expect(data.ports.every((port) => port.currentLabel === '')).toBe(true)
  })
})
