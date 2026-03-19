// Unified file I/O facade with native dialogs

import { dialog, BrowserWindow, app } from 'electron'
import { extname, join, resolve } from 'path'
import { readdirSync, existsSync } from 'fs'
import { FileData } from '../protocols/types'
import { readExcel, writeExcel, createExcelTemplate } from './excel-handler'
import { readCsv, writeCsv, createCsvTemplate } from './csv-handler'
import { readJson, writeJson } from './json-handler'

const FILE_FILTERS = [
  { name: 'Excel Files', extensions: ['xlsx'] },
  { name: 'CSV Files', extensions: ['csv'] },
  { name: 'JSON Files', extensions: ['json'] },
  { name: 'All Files', extensions: ['*'] },
]

const SAVE_FILTERS = [
  { name: 'Excel Files', extensions: ['xlsx'] },
  { name: 'CSV Files', extensions: ['csv'] },
  { name: 'JSON Files', extensions: ['json'] },
]

export async function openFile(): Promise<FileData | null> {
  const win = BrowserWindow.getFocusedWindow()
  const result = await dialog.showOpenDialog(win!, {
    title: 'Open Label File',
    filters: FILE_FILTERS,
    properties: ['openFile'],
  })

  if (result.canceled || result.filePaths.length === 0) return null
  const filePath = result.filePaths[0]
  return readFile(filePath)
}

export async function readFile(filePath: string): Promise<FileData> {
  const ext = extname(filePath).toLowerCase()
  switch (ext) {
    case '.xlsx':
      return readExcel(filePath)
    case '.csv':
      return readCsv(filePath)
    case '.json':
      return readJson(filePath)
    default:
      throw new Error(`Unsupported file type: ${ext}`)
  }
}

export async function saveFile(filePath: string, data: FileData): Promise<void> {
  const ext = extname(filePath).toLowerCase()
  switch (ext) {
    case '.xlsx':
      return writeExcel(filePath, data)
    case '.csv':
      return writeCsv(filePath, data)
    case '.json':
      return writeJson(filePath, data)
    default:
      throw new Error(`Unsupported file type: ${ext}`)
  }
}

export async function saveFileAs(data: FileData): Promise<string | null> {
  const win = BrowserWindow.getFocusedWindow()
  const result = await dialog.showSaveDialog(win!, {
    title: 'Save Label File',
    filters: SAVE_FILTERS,
    defaultPath: 'labels.xlsx',
  })

  if (result.canceled || !result.filePath) return null

  let filePath = result.filePath
  // Ensure extension
  const ext = extname(filePath).toLowerCase()
  if (!ext) filePath += '.xlsx'

  await saveFile(filePath, data)
  return filePath
}

export async function createTemplate(portCount = 32): Promise<string | null> {
  const win = BrowserWindow.getFocusedWindow()
  const result = await dialog.showSaveDialog(win!, {
    title: 'Create Template',
    filters: SAVE_FILTERS,
    defaultPath: `template_${portCount}x${portCount}.xlsx`,
  })

  if (result.canceled || !result.filePath) return null

  let filePath = result.filePath
  const ext = extname(filePath).toLowerCase()

  if (ext === '.csv') {
    createCsvTemplate(filePath, portCount)
  } else {
    if (!ext) filePath += '.xlsx'
    await createExcelTemplate(filePath, portCount)
  }

  return filePath
}

function getTemplatesDir(): string {
  // In production, resources are in the app's resource path
  // In dev, they're relative to the electron directory
  const prodPath = join(process.resourcesPath || '', 'templates')
  const devPath = resolve(__dirname, '..', '..', '..', 'resources', 'templates')

  if (existsSync(prodPath)) return prodPath
  if (existsSync(devPath)) return devPath

  // Fallback: try relative to app path
  const appPath = join(app.getAppPath(), 'resources', 'templates')
  return appPath
}

export function getDefaultTemplates(): Array<{ name: string; filename: string }> {
  const dir = getTemplatesDir()
  if (!existsSync(dir)) return []

  try {
    const files = readdirSync(dir).filter(f => f.endsWith('.xlsx'))
    return files.map(filename => {
      // Extract a friendly name: "Helix_16x16_Template.xlsx" -> "16x16 Template"
      const name = filename
        .replace(/^Helix_/, '')
        .replace(/\.xlsx$/, '')
        .replace(/_/g, ' ')
      return { name, filename }
    })
  } catch {
    return []
  }
}

export async function openDefaultTemplate(templateName: string): Promise<FileData | null> {
  const dir = getTemplatesDir()
  const filePath = join(dir, templateName)

  if (!existsSync(filePath)) {
    throw new Error(`Template not found: ${templateName}`)
  }

  return readExcel(filePath)
}
