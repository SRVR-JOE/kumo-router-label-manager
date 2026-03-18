// JSON file handler for label data

import { readFileSync, writeFileSync } from 'fs'
import { FileData, PortData } from '../protocols/types'

interface JsonFileFormat {
  version: string
  routerType?: string
  deviceName?: string
  ports: Array<{
    port: number
    type: 'INPUT' | 'OUTPUT'
    current_label: string
    new_label?: string | null
    current_label_line2?: string
    new_label_line2?: string | null
    current_color?: number
    new_color?: number | null
    notes?: string
  }>
}

export function readJson(filePath: string): FileData {
  const content = readFileSync(filePath, 'utf-8')
  let data: JsonFileFormat

  try {
    data = JSON.parse(content)
  } catch (e) {
    throw new Error(`Invalid JSON file: ${e}`)
  }

  if (!data.ports || !Array.isArray(data.ports)) {
    throw new Error('JSON file missing "ports" array')
  }

  const ports: PortData[] = data.ports.map((p, idx) => {
    if (typeof p.port !== 'number' || p.port < 1) {
      throw new Error(`Invalid port number in entry ${idx}`)
    }
    const type = (p.type || 'INPUT').toUpperCase() as 'INPUT' | 'OUTPUT'
    if (type !== 'INPUT' && type !== 'OUTPUT') {
      throw new Error(`Invalid type '${p.type}' in entry ${idx}`)
    }

    return {
      port: p.port,
      type,
      currentLabel: p.current_label || '',
      newLabel: p.new_label || null,
      currentLabelLine2: p.current_label_line2 || '',
      newLabelLine2: p.new_label_line2 || null,
      currentColor: p.current_color ?? 4,
      newColor: p.new_color ?? null,
      notes: p.notes || '',
    }
  })

  return { ports, filePath, fileType: 'json' }
}

export function writeJson(filePath: string, data: FileData): void {
  const output: JsonFileFormat = {
    version: '1.0',
    ports: data.ports.map(p => ({
      port: p.port,
      type: p.type,
      current_label: p.currentLabel,
      new_label: p.newLabel,
      current_label_line2: p.currentLabelLine2,
      new_label_line2: p.newLabelLine2,
      current_color: p.currentColor,
      new_color: p.newColor,
      notes: p.notes,
    })),
  }

  writeFileSync(filePath, JSON.stringify(output, null, 2), 'utf-8')
}
