import { contextBridge, ipcRenderer, IpcRendererEvent } from 'electron'
import type { Label, PortData, AppSettings, ConnectResult, UploadResult, Crosspoint, FileData, RouterType } from '../main/protocols/types'

export type HelixAPI = typeof helixAPI

const helixAPI = {
  // Router operations
  router: {
    connect: (ip: string, routerType?: RouterType): Promise<ConnectResult> =>
      ipcRenderer.invoke('router:connect', ip, routerType),
    disconnect: (): Promise<void> =>
      ipcRenderer.invoke('router:disconnect'),
    detectType: (ip: string): Promise<RouterType | null> =>
      ipcRenderer.invoke('router:detect-type', ip),
    download: (): Promise<Label[]> =>
      ipcRenderer.invoke('router:download'),
    upload: (labels: Label[]): Promise<UploadResult> =>
      ipcRenderer.invoke('router:upload', labels),
    getCrosspoints: (): Promise<Crosspoint[]> =>
      ipcRenderer.invoke('router:get-crosspoints'),
    setRoute: (output: number, input: number): Promise<boolean> =>
      ipcRenderer.invoke('router:set-route', output, input),
    scanSubnet: (baseIp: string): Promise<Array<{ ip: string; routerType: RouterType }>> =>
      ipcRenderer.invoke('router:scan-subnet', baseIp),
  },

  // File operations
  file: {
    open: (): Promise<FileData | null> =>
      ipcRenderer.invoke('file:open'),
    save: (path: string, data: { ports: PortData[] }): Promise<void> =>
      ipcRenderer.invoke('file:save', path, data),
    saveAs: (data: { ports: PortData[] }): Promise<string | null> =>
      ipcRenderer.invoke('file:save-as', data),
    createTemplate: (path: string, portCount: number): Promise<FileData | null> =>
      ipcRenderer.invoke('file:create-template', path, portCount),
    getRecent: (): Promise<string[]> =>
      ipcRenderer.invoke('file:get-recent'),
    getDefaultTemplates: (): Promise<string[]> =>
      ipcRenderer.invoke('file:get-default-templates'),
    openDefaultTemplate: (name: string): Promise<FileData | null> =>
      ipcRenderer.invoke('file:open-default-template', name),
  },

  // Settings
  settings: {
    get: (): Promise<AppSettings> =>
      ipcRenderer.invoke('settings:get'),
    set: (partial: Partial<AppSettings>): Promise<void> =>
      ipcRenderer.invoke('settings:set', partial),
  },

  // Events from main process
  on: (channel: string, callback: (...args: unknown[]) => void) => {
    const validChannels = [
      'progress',
      'connection-status',
      'error',
      'menu:new',
      'menu:open',
      'menu:save',
      'menu:save-as',
      'menu:create-template',
      'menu:connect',
      'menu:disconnect',
      'menu:download',
      'menu:upload',
      'menu:crosspoint',
      'menu:find-replace',
      'menu:auto-number',
      'menu:bulk-ops',
      'menu:statistics',
      'menu:settings',
      'menu:undo',
      'menu:redo',
      'menu:about',
      'scan-progress',
    ]
    if (validChannels.includes(channel)) {
      const subscription = (_event: IpcRendererEvent, ...args: unknown[]) => callback(...args)
      ipcRenderer.on(channel, subscription)
      return () => { ipcRenderer.removeListener(channel, subscription) }
    }
    return () => {}
  },

  // Remove all listeners for a channel — restricted to the same allowlist as on()
  removeAllListeners: (channel: string) => {
    const validChannels = [
      'progress', 'connection-status', 'error', 'scan-progress',
      'menu:new', 'menu:open', 'menu:save', 'menu:save-as', 'menu:create-template',
      'menu:connect', 'menu:disconnect', 'menu:download', 'menu:upload',
      'menu:crosspoint', 'menu:find-replace', 'menu:auto-number', 'menu:bulk-ops',
      'menu:statistics', 'menu:settings', 'menu:undo', 'menu:redo', 'menu:about',
    ]
    if (validChannels.includes(channel)) {
      ipcRenderer.removeAllListeners(channel)
    }
  },
}

contextBridge.exposeInMainWorld('helix', helixAPI)
