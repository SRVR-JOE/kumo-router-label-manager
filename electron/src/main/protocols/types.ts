// Router types and shared protocol definitions

export type RouterType = 'kumo' | 'videohub' | 'lightware'
export type PortType = 'INPUT' | 'OUTPUT'
export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error'

export interface Label {
  portNumber: number
  portType: PortType
  currentLabel: string
  newLabel: string | null
  currentLabelLine2: string
  newLabelLine2: string | null
  currentColor: number // 1-9
  newColor: number | null
  notes: string
}

export interface ConnectResult {
  success: boolean
  routerType: RouterType
  deviceName: string
  inputCount: number
  outputCount: number
  error?: string
}

// Per-port outcome of a single upload. One entry per port that had a pending
// change, regardless of how many underlying wire operations that port required
// (e.g. KUMO's label-line-1/line-2/color are three separate HTTP requests but
// collapse to one PortUploadResult per port here).
export interface PortUploadResult {
  portNumber: number
  portType: PortType
  ok: boolean
  error?: string
}

export interface UploadResult {
  successCount: number
  errorCount: number
  errors: string[]
  // Always populated (one entry per port with a pending change) whenever the
  // upload attempt reached the point of dispatching at least one port write.
  // Only left empty when the router rejected the batch before any per-port
  // detail could be established (e.g. an unexpected exception thrown before
  // dispatch) — callers must treat an empty array as "no per-port detail
  // available" and fall back to a conservative all-pending treatment.
  results: PortUploadResult[]
}

// Videohub-specific lock/take-mode state, parsed from the device's dump but
// not currently surfaced anywhere in the UI. A future UI could use this to
// grey out / block writes to outputs whose lock state isn't 'U' (unlocked)
// and to show whether the device is in "take" (confirm-before-switch) mode.
export interface VideohubLockState {
  output: number // 0-based, matches Crosspoint.output
  state: string // raw Blackmagic lock code: 'U' unlocked, 'O' owned by this connection, 'L' locked by someone else
}

export interface VideohubStatus {
  locks: VideohubLockState[]
  takeMode: boolean
}

export interface Crosspoint {
  output: number // 0-based
  input: number  // 0-based
}

export interface RouterInfo {
  ip: string
  routerType: RouterType
  deviceName: string
  inputCount: number
  outputCount: number
  firmwareVersion?: string
  protocolVersion?: string
}

// KUMO button color presets (1-9)
export const KUMO_COLORS: Record<number, { name: string; idle: string; active: string }> = {
  1: { name: 'Red',         idle: '#cb7676', active: '#fe0000' },
  2: { name: 'Orange',      idle: '#e6a52e', active: '#f76700' },
  3: { name: 'Yellow',      idle: '#d9cb7e', active: '#d7af00' },
  4: { name: 'Blue',        idle: '#87b4c8', active: '#009af4' },
  5: { name: 'Teal',        idle: '#64c896', active: '#00a263' },
  6: { name: 'Light Green', idle: '#ade68e', active: '#60b71f' },
  7: { name: 'Indigo',      idle: '#7888cb', active: '#3a5ef6' },
  8: { name: 'Purple',      idle: '#9b8ce1', active: '#8100f4' },
  9: { name: 'Pink',        idle: '#c84b91', active: '#f30088' },
}

export const KUMO_DEFAULT_COLOR = 4

export const KUMO_COLOR_NAMES: Record<number, string> = {
  1: 'Red', 2: 'Orange', 3: 'Yellow', 4: 'Blue', 5: 'Teal',
  6: 'Light Green', 7: 'Indigo', 8: 'Purple', 9: 'Pink',
}

// File data structures
export interface PortData {
  port: number
  type: PortType
  currentLabel: string
  newLabel: string | null
  currentLabelLine2: string
  newLabelLine2: string | null
  currentColor: number
  newColor: number | null
  notes: string
}

export interface FileData {
  ports: PortData[]
  filePath?: string
  fileType?: 'xlsx' | 'csv' | 'json'
}

// Saved router presets for quick connect
export interface SavedRouter {
  name: string
  ip: string
  routerType?: RouterType
}

// Settings
export interface AppSettings {
  defaultIp: string
  defaultFilePath: string
  autoConnect: boolean
  maxLabelLength: number
  recentFiles: string[]
  theme: 'dark' | 'light'
  windowBounds?: { x: number; y: number; width: number; height: number }
  savedRouters: SavedRouter[]
}

export const DEFAULT_SETTINGS: AppSettings = {
  defaultIp: '192.168.100.52',
  defaultFilePath: '',
  autoConnect: false,
  maxLabelLength: 255,
  recentFiles: [],
  theme: 'dark',
  savedRouters: [],
}
