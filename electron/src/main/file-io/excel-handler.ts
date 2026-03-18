// Excel file handler using ExcelJS
// 9-column layout: Port, Type, Current_Label, Current_Label_Line2, New_Label, New_Label_Line2, Current_Color, New_Color, Notes

import ExcelJS from 'exceljs'
import { FileData, PortData } from '../protocols/types'

const WORKSHEET_NAME = 'KUMO_Labels'
const HEADERS = ['Port', 'Type', 'Current_Label', 'Current_Label_Line2', 'New_Label', 'New_Label_Line2', 'Current_Color', 'New_Color', 'Notes']
const HEADER_FILL: ExcelJS.Fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4472C4' } }
const HEADER_FONT: Partial<ExcelJS.Font> = { bold: true, color: { argb: 'FFFFFFFF' }, size: 12 }

export async function readExcel(filePath: string): Promise<FileData> {
  const workbook = new ExcelJS.Workbook()
  await workbook.xlsx.readFile(filePath)

  const worksheet = workbook.getWorksheet(WORKSHEET_NAME)
  if (!worksheet) {
    const names = workbook.worksheets.map(ws => ws.name)
    throw new Error(`Worksheet '${WORKSHEET_NAME}' not found. Available: ${names.join(', ')}`)
  }

  // Detect column layout from header row
  const headerRow = worksheet.getRow(1)
  const colMap: Record<string, number> = {}
  headerRow.eachCell((cell, colNumber) => {
    if (cell.value) colMap[String(cell.value).trim()] = colNumber
  })

  const hasLine2 = 'Current_Label_Line2' in colMap
  const hasColor = 'Current_Color' in colMap

  const ports: PortData[] = []
  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return // skip header
    const portVal = row.getCell(1).value
    if (portVal === null || portVal === undefined) return

    const port = typeof portVal === 'number' ? portVal : parseInt(String(portVal), 10)
    if (isNaN(port)) return

    const type = (String(row.getCell(2).value || 'INPUT').trim().toUpperCase() as 'INPUT' | 'OUTPUT')

    let currentLabel = String(row.getCell(3).value || '').trim()
    let currentLabelLine2 = ''
    let newLabel: string | null = null
    let newLabelLine2: string | null = null
    let currentColor = 4
    let newColor: number | null = null
    let notes = ''

    if (hasLine2) {
      currentLabelLine2 = String(row.getCell(colMap['Current_Label_Line2']).value || '').trim()
      const nlCell = row.getCell(colMap['New_Label'] || 5).value
      newLabel = nlCell ? String(nlCell).trim() : null
      const nl2Cell = row.getCell(colMap['New_Label_Line2'] || 6).value
      newLabelLine2 = nl2Cell ? String(nl2Cell).trim() : null
    } else {
      const nlCell = row.getCell(4).value
      newLabel = nlCell ? String(nlCell).trim() : null
    }

    if (hasColor) {
      const ccCell = row.getCell(colMap['Current_Color']).value
      if (ccCell !== null && ccCell !== undefined && String(ccCell).trim()) {
        currentColor = parseInt(String(ccCell), 10)
        if (isNaN(currentColor) || currentColor < 1 || currentColor > 9) currentColor = 4
      }
      const ncCol = colMap['New_Color']
      if (ncCol) {
        const ncCell = row.getCell(ncCol).value
        if (ncCell !== null && ncCell !== undefined && String(ncCell).trim()) {
          const nc = parseInt(String(ncCell), 10)
          newColor = (!isNaN(nc) && nc >= 1 && nc <= 9) ? nc : null
        }
      }
    }

    const notesCol = colMap['Notes'] || (hasLine2 ? 9 : 5)
    const notesCell = row.getCell(notesCol).value
    notes = notesCell ? String(notesCell).trim() : ''

    // Normalize empty strings to null for new labels
    if (newLabel === '') newLabel = null
    if (newLabelLine2 === '') newLabelLine2 = null

    ports.push({ port, type, currentLabel, newLabel, currentLabelLine2, newLabelLine2, currentColor, newColor, notes })
  })

  return { ports, filePath, fileType: 'xlsx' }
}

export async function writeExcel(filePath: string, data: FileData): Promise<void> {
  const workbook = new ExcelJS.Workbook()
  const worksheet = workbook.addWorksheet(WORKSHEET_NAME)

  // Headers
  const headerRow = worksheet.addRow(HEADERS)
  headerRow.eachCell((cell) => {
    cell.fill = HEADER_FILL
    cell.font = HEADER_FONT
    cell.alignment = { horizontal: 'center', vertical: 'middle' }
  })

  // Data rows
  for (const p of data.ports) {
    worksheet.addRow([
      p.port,
      p.type,
      p.currentLabel,
      p.currentLabelLine2,
      p.newLabel || '',
      p.newLabelLine2 || '',
      p.currentColor,
      p.newColor ?? '',
      p.notes,
    ])
  }

  // Type column data validation
  const lastRow = data.ports.length + 1
  worksheet.getColumn(2).eachCell((cell, rowNumber) => {
    if (rowNumber > 1) {
      cell.alignment = { horizontal: 'center' }
    }
  })
  worksheet.getColumn(1).eachCell((cell, rowNumber) => {
    if (rowNumber > 1) cell.alignment = { horizontal: 'center' }
  })
  worksheet.getColumn(7).eachCell((cell, rowNumber) => {
    if (rowNumber > 1) cell.alignment = { horizontal: 'center' }
  })
  worksheet.getColumn(8).eachCell((cell, rowNumber) => {
    if (rowNumber > 1) cell.alignment = { horizontal: 'center' }
  })

  // Auto-fit columns
  worksheet.columns.forEach((col) => {
    let maxLen = 10
    col.eachCell?.({ includeEmpty: false }, (cell) => {
      const len = String(cell.value || '').length
      if (len > maxLen) maxLen = len
    })
    col.width = Math.min(maxLen + 2, 50)
  })

  // Freeze header
  worksheet.views = [{ state: 'frozen', ySplit: 1 }]

  await workbook.xlsx.writeFile(filePath)
}

export async function createExcelTemplate(filePath: string, portCount = 32): Promise<void> {
  const ports: PortData[] = []
  for (let i = 1; i <= portCount; i++) {
    ports.push({ port: i, type: 'INPUT', currentLabel: '', newLabel: null, currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '' })
  }
  for (let i = 1; i <= portCount; i++) {
    ports.push({ port: i, type: 'OUTPUT', currentLabel: '', newLabel: null, currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '' })
  }
  await writeExcel(filePath, { ports })
}
