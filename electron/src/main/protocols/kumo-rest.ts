// AJA KUMO REST API client
// Ports: HTTP 80 (GET /config?action=get|set&configid=0&paramid=...)

import { Label, ConnectResult, UploadResult, KUMO_DEFAULT_COLOR } from './types'

const MAX_CONCURRENT = 32
const REQUEST_TIMEOUT = 4000
const CONNECT_TIMEOUT = 3000

// eParamID helpers
function sourceNameParam(port: number, line = 1): string {
  return `eParamID_XPT_Source${port}_Line_${line}`
}
function destNameParam(port: number, line = 1): string {
  return `eParamID_XPT_Destination${port}_Line_${line}`
}
function destStatusParam(port: number): string {
  return `eParamID_XPT_Destination${port}_Status`
}
function buttonColorParam(port: number, portType: string): string {
  const block = Math.floor((port - 1) / 16)
  const offset = (port - 1) % 16
  let base = block * 32 + offset + 1
  if (portType.toUpperCase() === 'OUTPUT') base += 16
  return `eParamID_Button_Settings_${base}`
}

function getUrl(ip: string, paramId: string): string {
  return `http://${ip}/config?action=get&configid=0&paramid=${paramId}`
}
function setUrl(ip: string, paramId: string, value: string): string {
  return `http://${ip}/config?action=set&configid=0&paramid=${paramId}&value=${encodeURIComponent(value)}`
}

async function fetchWithTimeout(url: string, timeout = REQUEST_TIMEOUT): Promise<Response> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeout)
  try {
    return await fetch(url, { signal: controller.signal })
  } finally {
    clearTimeout(timer)
  }
}

function parseParamResponse(json: Record<string, unknown>): string | null {
  if (json.value_name && String(json.value_name).trim()) {
    return String(json.value_name).trim()
  }
  if (json.value && String(json.value).trim()) {
    return String(json.value).trim()
  }
  return null
}

function parseButtonColor(value: string | null): number {
  if (!value) return KUMO_DEFAULT_COLOR
  // Try JSON: {"classes":"color_N"}
  try {
    const data = JSON.parse(value)
    const classes = data.classes || ''
    const match = classes.match(/color_(\d+)/)
    if (match) {
      const id = parseInt(match[1], 10)
      if (id >= 1 && id <= 9) return id
    }
  } catch { /* ignore */ }
  // Fallback: search raw string
  const match = value.match(/color_(\d+)/)
  if (match) {
    const id = parseInt(match[1], 10)
    if (id >= 1 && id <= 9) return id
  }
  return KUMO_DEFAULT_COLOR
}

function encodeButtonColor(colorId: number): string {
  if (colorId < 1 || colorId > 9) colorId = KUMO_DEFAULT_COLOR
  return `{\\"classes\\":\\"color_${colorId}\\"}`
}

// Concurrency-limited parallel execution
async function parallelLimit<T>(
  tasks: (() => Promise<T>)[],
  limit: number,
  onProgress?: (done: number, total: number) => void
): Promise<T[]> {
  const results: T[] = new Array(tasks.length)
  let nextIndex = 0
  let completed = 0

  async function worker(): Promise<void> {
    while (nextIndex < tasks.length) {
      const idx = nextIndex++
      try {
        results[idx] = await tasks[idx]()
      } catch (e) {
        results[idx] = e as T
      }
      completed++
      if (onProgress && completed % 16 === 0) {
        onProgress(completed, tasks.length)
      }
    }
  }

  const workers = Array.from({ length: Math.min(limit, tasks.length) }, () => worker())
  await Promise.all(workers)
  if (onProgress) onProgress(tasks.length, tasks.length)
  return results
}

export async function kumoTestConnection(ip: string): Promise<boolean> {
  try {
    const resp = await fetchWithTimeout(getUrl(ip, 'eParamID_SysName'), CONNECT_TIMEOUT)
    if (!resp.ok) return false
    const json = await resp.json()
    return parseParamResponse(json) !== null
  } catch {
    return false
  }
}

export async function kumoGetSystemName(ip: string): Promise<string> {
  try {
    const resp = await fetchWithTimeout(getUrl(ip, 'eParamID_SysName'))
    const json = await resp.json()
    return parseParamResponse(json) || 'KUMO'
  } catch {
    return 'KUMO'
  }
}

export async function kumoGetFirmwareVersion(ip: string): Promise<string> {
  try {
    const resp = await fetchWithTimeout(getUrl(ip, 'eParamID_SWVersion'))
    const json = await resp.json()
    return parseParamResponse(json) || 'Unknown'
  } catch {
    return 'Unknown'
  }
}

export async function kumoDetectPortCount(ip: string): Promise<number> {
  // Probe 64 and 32 in parallel
  const [r64, r32] = await Promise.all([
    fetchWithTimeout(getUrl(ip, sourceNameParam(33)), CONNECT_TIMEOUT)
      .then(r => r.json()).catch(() => null),
    fetchWithTimeout(getUrl(ip, sourceNameParam(17)), CONNECT_TIMEOUT)
      .then(r => r.json()).catch(() => null),
  ])
  if (r64 && parseParamResponse(r64)) return 64
  if (r32 && parseParamResponse(r32)) return 32
  return 16
}

export async function kumoConnect(ip: string): Promise<ConnectResult> {
  const isConnected = await kumoTestConnection(ip)
  if (!isConnected) {
    return { success: false, routerType: 'kumo', deviceName: '', inputCount: 0, outputCount: 0, error: `Cannot connect to KUMO at ${ip}` }
  }
  const [deviceName, portCount] = await Promise.all([
    kumoGetSystemName(ip),
    kumoDetectPortCount(ip),
  ])
  return {
    success: true,
    routerType: 'kumo',
    deviceName,
    inputCount: portCount,
    outputCount: portCount,
  }
}

export async function kumoDownloadLabels(
  ip: string,
  portCount: number,
  onProgress?: (done: number, total: number) => void
): Promise<Label[]> {
  type FetchResult = { port: number; portType: 'INPUT' | 'OUTPUT'; line: number; label: string | null }

  const tasks: (() => Promise<FetchResult>)[] = []

  // Build all fetch tasks for inputs and outputs, lines 1 and 2
  for (const portType of ['INPUT', 'OUTPUT'] as const) {
    for (let port = 1; port <= portCount; port++) {
      for (const line of [1, 2]) {
        const paramId = portType === 'INPUT' ? sourceNameParam(port, line) : destNameParam(port, line)
        tasks.push(async () => {
          try {
            const resp = await fetchWithTimeout(getUrl(ip, paramId))
            const json = await resp.json()
            return { port, portType, line, label: parseParamResponse(json) }
          } catch {
            return { port, portType, line, label: null }
          }
        })
      }
    }
  }

  const results = await parallelLimit(tasks, MAX_CONCURRENT, onProgress)

  // Build label map
  const labelMap = new Map<string, { l1: string; l2: string }>()
  for (let port = 1; port <= portCount; port++) {
    labelMap.set(`INPUT-${port}`, { l1: `Source ${port}`, l2: '' })
    labelMap.set(`OUTPUT-${port}`, { l1: `Dest ${port}`, l2: '' })
  }

  for (const r of results) {
    if (r && !(r instanceof Error)) {
      const key = `${r.portType}-${r.port}`
      const entry = labelMap.get(key)
      if (entry && r.label) {
        if (r.line === 1) entry.l1 = r.label
        else entry.l2 = r.label
      }
    }
  }

  // Fetch colors in parallel
  const colorTasks: (() => Promise<{ port: number; portType: 'INPUT' | 'OUTPUT'; color: number }>)[] = []
  for (const portType of ['INPUT', 'OUTPUT'] as const) {
    for (let port = 1; port <= portCount; port++) {
      const paramId = buttonColorParam(port, portType)
      colorTasks.push(async () => {
        try {
          const resp = await fetchWithTimeout(getUrl(ip, paramId))
          const json = await resp.json()
          const raw = json.value || json.value_name || null
          const color = parseButtonColor(typeof raw === 'string' ? raw : null)
          return { port, portType, color }
        } catch {
          return { port, portType, color: KUMO_DEFAULT_COLOR }
        }
      })
    }
  }

  const colorResults = await parallelLimit(colorTasks, MAX_CONCURRENT)
  const colorMap = new Map<string, number>()
  for (const r of colorResults) {
    if (r && !(r instanceof Error)) {
      colorMap.set(`${r.portType}-${r.port}`, r.color)
    }
  }

  // Assemble Label array
  const labels: Label[] = []
  for (const portType of ['INPUT', 'OUTPUT'] as const) {
    for (let port = 1; port <= portCount; port++) {
      const key = `${portType}-${port}`
      const entry = labelMap.get(key)!
      labels.push({
        portNumber: port,
        portType,
        currentLabel: entry.l1,
        newLabel: null,
        currentLabelLine2: entry.l2,
        newLabelLine2: null,
        currentColor: colorMap.get(key) ?? KUMO_DEFAULT_COLOR,
        newColor: null,
        notes: '',
      })
    }
  }

  return labels
}

export async function kumoUploadLabels(
  ip: string,
  labels: Label[],
  onProgress?: (done: number, total: number) => void
): Promise<UploadResult> {
  const changes = labels.filter(l =>
    (l.newLabel !== null && l.newLabel !== l.currentLabel) ||
    (l.newLabelLine2 !== null && l.newLabelLine2 !== l.currentLabelLine2) ||
    (l.newColor !== null && l.newColor !== l.currentColor)
  )
  if (changes.length === 0) return { successCount: 0, errorCount: 0, errors: [] }

  const tasks: (() => Promise<{ success: boolean; error?: string }>)[] = []

  for (const label of changes) {
    // Label line 1
    if (label.newLabel !== null && label.newLabel !== label.currentLabel) {
      const paramId = label.portType === 'INPUT'
        ? sourceNameParam(label.portNumber, 1)
        : destNameParam(label.portNumber, 1)
      tasks.push(async () => {
        try {
          const resp = await fetchWithTimeout(setUrl(ip, paramId, label.newLabel!))
          return { success: resp.ok }
        } catch (e) {
          return { success: false, error: `${label.portType} ${label.portNumber} L1: ${e}` }
        }
      })
    }
    // Label line 2
    if (label.newLabelLine2 !== null && label.newLabelLine2 !== label.currentLabelLine2) {
      const paramId = label.portType === 'INPUT'
        ? sourceNameParam(label.portNumber, 2)
        : destNameParam(label.portNumber, 2)
      tasks.push(async () => {
        try {
          const resp = await fetchWithTimeout(setUrl(ip, paramId, label.newLabelLine2!))
          return { success: resp.ok }
        } catch (e) {
          return { success: false, error: `${label.portType} ${label.portNumber} L2: ${e}` }
        }
      })
    }
    // Color
    if (label.newColor !== null && label.newColor !== label.currentColor) {
      const paramId = buttonColorParam(label.portNumber, label.portType)
      const colorValue = encodeButtonColor(label.newColor)
      tasks.push(async () => {
        try {
          const resp = await fetchWithTimeout(setUrl(ip, paramId, colorValue))
          return { success: resp.ok }
        } catch (e) {
          return { success: false, error: `${label.portType} ${label.portNumber} color: ${e}` }
        }
      })
    }
  }

  const results = await parallelLimit(tasks, MAX_CONCURRENT, onProgress)
  let successCount = 0
  let errorCount = 0
  const errors: string[] = []

  for (const r of results) {
    if (r && !(r instanceof Error) && r.success) {
      successCount++
    } else {
      errorCount++
      if (r && !(r instanceof Error) && r.error) errors.push(r.error)
    }
  }

  return { successCount, errorCount, errors }
}

export async function kumoGetCrosspoints(ip: string, outputCount: number): Promise<{ output: number; input: number }[]> {
  const tasks: (() => Promise<{ output: number; input: number }>)[] = []
  for (let dest = 1; dest <= outputCount; dest++) {
    tasks.push(async () => {
      try {
        const resp = await fetchWithTimeout(getUrl(ip, destStatusParam(dest)))
        const json = await resp.json()
        const val = parseParamResponse(json)
        const input = val ? parseInt(val, 10) : 0
        return { output: dest - 1, input: isNaN(input) ? 0 : input - 1 }
      } catch {
        return { output: dest - 1, input: 0 }
      }
    })
  }
  return parallelLimit(tasks, MAX_CONCURRENT)
}

export async function kumoSetRoute(ip: string, outputPort: number, inputPort: number): Promise<boolean> {
  // output/input are 1-based for KUMO
  const paramId = destStatusParam(outputPort)
  try {
    const resp = await fetchWithTimeout(setUrl(ip, paramId, String(inputPort)))
    return resp.ok
  } catch {
    return false
  }
}
