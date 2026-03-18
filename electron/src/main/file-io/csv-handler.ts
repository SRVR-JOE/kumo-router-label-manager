// CSV file handler using Papa Parse

import { readFileSync, writeFileSync } from 'fs'
import Papa from 'papaparse'
import { FileData, PortData } from '../protocols/types'

const COLUMNS = ['Port', 'Type', 'Current_Label', 'Current_Label_Line2', 'New_Label', 'New_Label_Line2', 'Current_Color', 'New_Color', 'Notes']
const REQUIRED_COLUMNS = ['Port', 'Type', 'Current_Label', 'New_Label', 'Notes']

export function readCsv(filePath: string): FileData {
  const content = readFileSync(filePath, 'utf-8')
  const parsed = Papa.parse<Record<string, string>>(content, {
    header: true,
    skipEmptyLines: true,
    transformHeader: (h) => h.trim(),
  })

  if (parsed.errors.length > 0 && parsed.errors.some(e => e.type === 'Delimiter')) {
    throw new Error(`CSV parse error: ${parsed.errors[0].message}`)
  }

  // Check required columns
  const fields = parsed.meta.fields || []
  const missing = REQUIRED_COLUMNS.filter(c => !fields.includes(c))
  if (missing.length > 0) {
    throw new Error(`CSV missing required columns: ${missing.join(', ')}`)
  }

  const hasLine2 = fields.includes('Current_Label_Line2')
  const hasColor = fields.includes('Current_Color')

  const ports: PortData[] = parsed.data.map((row, idx) => {
    const port = parseInt(row['Port'], 10)
    if (isNaN(port)) throw new Error(`Invalid port number in row ${idx + 2}`)

    const type = (row['Type'] || 'INPUT').trim().toUpperCase() as 'INPUT' | 'OUTPUT'
    if (type !== 'INPUT' && type !== 'OUTPUT') throw new Error(`Invalid type '${type}' in row ${idx + 2}`)

    const currentLabel = (row['Current_Label'] || '').trim()
    const nlRaw = (row['New_Label'] || '').trim()
    const newLabel = nlRaw || null

    const currentLabelLine2 = hasLine2 ? (row['Current_Label_Line2'] || '').trim() : ''
    const nl2Raw = hasLine2 ? (row['New_Label_Line2'] || '').trim() : ''
    const newLabelLine2 = nl2Raw || null

    let currentColor = 4
    let newColor: number | null = null
    if (hasColor) {
      const ccRaw = (row['Current_Color'] || '').trim()
      if (ccRaw) {
        const cc = parseInt(ccRaw, 10)
        currentColor = (!isNaN(cc) && cc >= 1 && cc <= 9) ? cc : 4
      }
      const ncRaw = (row['New_Color'] || '').trim()
      if (ncRaw) {
        const nc = parseInt(ncRaw, 10)
        newColor = (!isNaN(nc) && nc >= 1 && nc <= 9) ? nc : null
      }
    }

    const notes = (row['Notes'] || '').trim()

    return { port, type, currentLabel, newLabel, currentLabelLine2, newLabelLine2, currentColor, newColor, notes }
  })

  return { ports, filePath, fileType: 'csv' }
}

export function writeCsv(filePath: string, data: FileData): void {
  const rows = data.ports.map(p => ({
    Port: p.port,
    Type: p.type,
    Current_Label: p.currentLabel,
    Current_Label_Line2: p.currentLabelLine2,
    New_Label: p.newLabel || '',
    New_Label_Line2: p.newLabelLine2 || '',
    Current_Color: p.currentColor,
    New_Color: p.newColor ?? '',
    Notes: p.notes,
  }))

  const csv = Papa.unparse(rows, {
    columns: COLUMNS,
    quotes: true,
    newline: '\n',
  })

  writeFileSync(filePath, csv, 'utf-8')
}

export function createCsvTemplate(filePath: string, portCount = 32): void {
  const ports: PortData[] = []
  for (let i = 1; i <= portCount; i++) {
    ports.push({ port: i, type: 'INPUT', currentLabel: '', newLabel: null, currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '' })
  }
  for (let i = 1; i <= portCount; i++) {
    ports.push({ port: i, type: 'OUTPUT', currentLabel: '', newLabel: null, currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '' })
  }
  writeCsv(filePath, { ports })
}
