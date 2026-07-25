import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import * as fs from 'fs'
import * as os from 'os'
import * as path from 'path'

// file-agent.ts imports { dialog, BrowserWindow, app } from 'electron' at module
// scope, purely to support the dialog-driven functions (openFile/saveFileAs/
// createTemplate/getDefaultTemplates). None of those are exercised here — we
// only test the pure extension-dispatch logic (readFile/saveFile) — but the
// module can't even be imported in a Node test process without a stub since
// the real 'electron' module only resolves inside an Electron runtime.
vi.mock('electron', () => ({
  dialog: { showOpenDialog: vi.fn(), showSaveDialog: vi.fn() },
  BrowserWindow: { getFocusedWindow: vi.fn(() => null) },
  app: { getAppPath: vi.fn(() => '') },
}))

import { readFile, saveFile } from './file-agent'
import type { FileData } from '../protocols/types'

let dir: string

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'helix-file-agent-test-'))
})

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true })
})

describe('readFile extension dispatch', () => {
  it('reads a .json file via the JSON handler', async () => {
    const p = path.join(dir, 'data.json')
    fs.writeFileSync(p, JSON.stringify({ ports: [{ port: 1, type: 'INPUT', current_label: 'CAM 1' }] }))
    const data = await readFile(p)
    expect(data.fileType).toBe('json')
    expect(data.ports[0].currentLabel).toBe('CAM 1')
  })

  it('reads a .csv file via the CSV handler', async () => {
    const p = path.join(dir, 'data.csv')
    fs.writeFileSync(p, 'Port,Type,Current_Label,New_Label,Notes\n1,INPUT,CAM 1,,\n')
    const data = await readFile(p)
    expect(data.fileType).toBe('csv')
    expect(data.ports[0].currentLabel).toBe('CAM 1')
  })

  it('dispatches on extension case-insensitively', async () => {
    const p = path.join(dir, 'DATA.JSON')
    fs.writeFileSync(p, JSON.stringify({ ports: [] }))
    const data = await readFile(p)
    expect(data.fileType).toBe('json')
  })

  it('throws for an unsupported extension', async () => {
    const p = path.join(dir, 'data.txt')
    fs.writeFileSync(p, 'irrelevant')
    await expect(readFile(p)).rejects.toThrow(/Unsupported file type/)
  })
})

describe('saveFile extension dispatch', () => {
  const sampleData: FileData = {
    ports: [
      {
        port: 1, type: 'INPUT', currentLabel: 'CAM 1', newLabel: null,
        currentLabelLine2: '', newLabelLine2: null, currentColor: 4, newColor: null, notes: '',
      },
    ],
  }

  it('writes a .json file', async () => {
    const p = path.join(dir, 'out.json')
    await saveFile(p, sampleData)
    const raw = JSON.parse(fs.readFileSync(p, 'utf-8'))
    expect(raw.ports[0].current_label).toBe('CAM 1')
  })

  it('writes a .csv file', async () => {
    const p = path.join(dir, 'out.csv')
    await saveFile(p, sampleData)
    const raw = fs.readFileSync(p, 'utf-8')
    expect(raw).toContain('CAM 1')
  })

  it('writes a .xlsx file', async () => {
    const p = path.join(dir, 'out.xlsx')
    await saveFile(p, sampleData)
    expect(fs.existsSync(p)).toBe(true)
  })

  it('throws for an unsupported extension', async () => {
    const p = path.join(dir, 'out.bogus')
    await expect(saveFile(p, sampleData)).rejects.toThrow(/Unsupported file type/)
  })
})
