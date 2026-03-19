// Generate professionally styled default Excel templates for Helix Label Manager
// Usage: npx tsx scripts/generate-templates.ts

import ExcelJS from 'exceljs'
import { resolve, dirname } from 'path'
import { mkdirSync } from 'fs'

const WORKSHEET_NAME = 'KUMO_Labels'
const HEADERS = [
  'Port', 'Type', 'Current_Label', 'Current_Label_Line2',
  'New_Label', 'New_Label_Line2', 'Current_Color', 'New_Color', 'Notes',
]

// Column config: [header, width, alignment, isEditField]
const COLUMN_CONFIG: Array<{
  header: string
  width: number
  alignment: 'center' | 'left'
  editField: boolean
}> = [
  { header: 'Port',                width: 8,  alignment: 'center', editField: false },
  { header: 'Type',                width: 10, alignment: 'center', editField: false },
  { header: 'Current_Label',      width: 25, alignment: 'left',   editField: false },
  { header: 'Current_Label_Line2', width: 25, alignment: 'left',   editField: false },
  { header: 'New_Label',          width: 25, alignment: 'left',   editField: true },
  { header: 'New_Label_Line2',    width: 25, alignment: 'left',   editField: true },
  { header: 'Current_Color',      width: 14, alignment: 'center', editField: false },
  { header: 'New_Color',          width: 14, alignment: 'center', editField: true },
  { header: 'Notes',              width: 35, alignment: 'left',   editField: false },
]

// Style constants
const ACCENT_PURPLE = 'FF7B2FBE'
const HEADER_FONT: Partial<ExcelJS.Font> = {
  bold: true,
  color: { argb: 'FFFFFFFF' },
  size: 11,
  name: 'Calibri',
}
const HEADER_FILL: ExcelJS.Fill = {
  type: 'pattern',
  pattern: 'solid',
  fgColor: { argb: ACCENT_PURPLE },
}
const HEADER_BORDER_BOTTOM: Partial<ExcelJS.Border> = {
  style: 'thin',
  color: { argb: 'FF463C5A' },
}

const DATA_FONT: Partial<ExcelJS.Font> = {
  name: 'Calibri',
  size: 10,
  color: { argb: 'FF2D2640' },
}
const DATA_BORDER: Partial<ExcelJS.Borders> = {
  top: { style: 'thin', color: { argb: 'FFD4CEE0' } },
  bottom: { style: 'thin', color: { argb: 'FFD4CEE0' } },
  left: { style: 'thin', color: { argb: 'FFD4CEE0' } },
  right: { style: 'thin', color: { argb: 'FFD4CEE0' } },
}

const ROW_FILL_EVEN: ExcelJS.Fill = {
  type: 'pattern',
  pattern: 'solid',
  fgColor: { argb: 'FFF3F0F7' },
}
const ROW_FILL_ODD: ExcelJS.Fill = {
  type: 'pattern',
  pattern: 'solid',
  fgColor: { argb: 'FFE8E3F0' },
}

const EDIT_FIELD_FILL: ExcelJS.Fill = {
  type: 'pattern',
  pattern: 'solid',
  fgColor: { argb: 'FFFFF9E6' },
}

async function generateTemplate(portCount: number, outputPath: string): Promise<void> {
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'Helix Label Manager'
  workbook.created = new Date()

  const worksheet = workbook.addWorksheet(WORKSHEET_NAME)

  // --- Column widths ---
  worksheet.columns = COLUMN_CONFIG.map(col => ({
    header: col.header,
    width: col.width,
  }))

  // --- Header row styling ---
  const headerRow = worksheet.getRow(1)
  headerRow.height = 28
  headerRow.eachCell((cell, colNumber) => {
    cell.fill = HEADER_FILL
    cell.font = HEADER_FONT
    cell.alignment = { horizontal: 'center', vertical: 'middle' }
    cell.border = {
      bottom: HEADER_BORDER_BOTTOM,
    }
  })

  // --- Auto-filter on header row ---
  worksheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: HEADERS.length },
  }

  // --- Data rows ---
  const totalRows = portCount * 2

  // Inputs first, then outputs
  for (let i = 0; i < portCount; i++) {
    const portNum = i + 1
    worksheet.addRow([
      portNum,
      'INPUT',
      `Input ${portNum}`,
      null,  // Current_Label_Line2
      null,  // New_Label (empty)
      null,  // New_Label_Line2 (empty)
      4,     // Current_Color (Blue default)
      null,  // New_Color (empty)
      null,  // Notes
    ])
  }

  for (let i = 0; i < portCount; i++) {
    const portNum = i + 1
    worksheet.addRow([
      portNum,
      'OUTPUT',
      `Output ${portNum}`,
      null,
      null,
      null,
      4,
      null,
      null,
    ])
  }

  // --- Style data rows ---
  for (let rowIdx = 2; rowIdx <= totalRows + 1; rowIdx++) {
    const row = worksheet.getRow(rowIdx)
    row.height = 22
    const isEven = (rowIdx - 2) % 2 === 0
    const baseFill = isEven ? ROW_FILL_EVEN : ROW_FILL_ODD

    row.eachCell({ includeEmpty: true }, (cell, colNumber) => {
      const colConfig = COLUMN_CONFIG[colNumber - 1]
      if (!colConfig) return

      cell.font = DATA_FONT
      cell.border = DATA_BORDER
      cell.alignment = {
        horizontal: colConfig.alignment,
        vertical: 'middle',
      }

      // Edit-field columns get the yellow highlight, others get alternating rows
      if (colConfig.editField) {
        cell.fill = EDIT_FIELD_FILL
      } else {
        cell.fill = baseFill
      }
    })
  }

  // --- Data validation: Type column (column 2) ---
  const lastDataRow = totalRows + 1
  for (let r = 2; r <= lastDataRow; r++) {
    worksheet.getCell(r, 2).dataValidation = {
      type: 'list',
      allowBlank: false,
      formulae: ['"INPUT,OUTPUT"'],
      showErrorMessage: true,
      errorTitle: 'Invalid Type',
      error: 'Please select INPUT or OUTPUT',
    }
  }

  // --- Data validation: New_Color column (column 8) ---
  for (let r = 2; r <= lastDataRow; r++) {
    worksheet.getCell(r, 8).dataValidation = {
      type: 'list',
      allowBlank: true,
      formulae: ['"1,2,3,4,5,6,7,8,9"'],
      showErrorMessage: true,
      errorTitle: 'Invalid Color',
      error: 'Color must be 1-9 (1=Red, 2=Orange, 3=Yellow, 4=Blue, 5=Teal, 6=Light Green, 7=Indigo, 8=Purple, 9=Pink)',
    }
  }

  // --- Conditional formatting: highlight row if New_Label is not empty ---
  // ExcelJS supports conditional formatting via worksheet.addConditionalFormatting
  // Apply to each column in the row range
  for (let col = 1; col <= HEADERS.length; col++) {
    const colLetter = columnLetter(col)
    const newLabelCol = columnLetter(5) // New_Label is column E

    worksheet.addConditionalFormatting({
      ref: `${colLetter}2:${colLetter}${lastDataRow}`,
      rules: [
        {
          type: 'expression',
          formulae: [`$${newLabelCol}2<>""`],
          priority: 1,
          style: {
            fill: {
              type: 'pattern',
              pattern: 'solid',
              bgColor: { argb: 'FFE8F5E9' },
            },
          },
        },
      ],
    })
  }

  // --- Freeze header row ---
  worksheet.views = [{ state: 'frozen', ySplit: 1, xSplit: 0 }]

  // --- Print setup ---
  worksheet.pageSetup = {
    orientation: 'landscape',
    fitToPage: true,
    fitToWidth: 1,
    fitToHeight: 0,
    printArea: `A1:I${lastDataRow}`,
  }

  // Write the file
  await workbook.xlsx.writeFile(outputPath)
  console.log(`  Generated: ${outputPath} (${portCount} inputs + ${portCount} outputs = ${totalRows} rows)`)
}

function columnLetter(colNumber: number): string {
  let letter = ''
  let num = colNumber
  while (num > 0) {
    const mod = (num - 1) % 26
    letter = String.fromCharCode(65 + mod) + letter
    num = Math.floor((num - 1) / 26)
  }
  return letter
}

async function main(): Promise<void> {
  const templatesDir = resolve(__dirname, '..', 'resources', 'templates')
  mkdirSync(templatesDir, { recursive: true })

  console.log('Generating Helix Label Manager default templates...')
  console.log(`Output directory: ${templatesDir}\n`)

  const templates = [
    { portCount: 8,  filename: 'Helix_8x8_Template.xlsx' },
    { portCount: 16, filename: 'Helix_16x16_Template.xlsx' },
    { portCount: 20, filename: 'Helix_20x20_Template.xlsx' },
    { portCount: 24, filename: 'Helix_24x24_Template.xlsx' },
    { portCount: 32, filename: 'Helix_32x32_Template.xlsx' },
    { portCount: 40, filename: 'Helix_40x40_Template.xlsx' },
    { portCount: 64, filename: 'Helix_64x64_Template.xlsx' },
  ]

  for (const tmpl of templates) {
    await generateTemplate(tmpl.portCount, resolve(templatesDir, tmpl.filename))
  }

  console.log('\nDone! All templates generated successfully.')
}

main().catch(err => {
  console.error('Failed to generate templates:', err)
  process.exit(1)
})
