import { contextBridge, ipcRenderer } from 'electron'

export type HelixAPI = typeof helixAPI

const helixAPI = {
  // Router operations
  router: {
    connect: (ip: string, routerType?: string) =>
      ipcRenderer.invoke('router:connect', ip, routerType),
    disconnect: () =>
      ipcRenderer.invoke('router:disconnect'),
    detectType: (ip: string) =>
      ipcRenderer.invoke('router:detect-type', ip),
    download: () =>
      ipcRenderer.invoke('router:download'),
    upload: (labels: unknown[]) =>
      ipcRenderer.invoke('router:upload', labels),
    getCrosspoints: () =>
      ipcRenderer.invoke('router:get-crosspoints'),
    setRoute: (output: number, input: number) =>
      ipcRenderer.invoke('router:set-route', output, input),
    scanSubnet: (baseIp: string) =>
      ipcRenderer.invoke('router:scan-subnet', baseIp),
  },

  // File operations
  file: {
    open: (filters?: unknown) =>
      ipcRenderer.invoke('file:open', filters),
    save: (path: string, data: unknown) =>
      ipcRenderer.invoke('file:save', path, data),
    saveAs: (data: unknown) =>
      ipcRenderer.invoke('file:save-as', data),
    createTemplate: (path: string, portCount: number) =>
      ipcRenderer.invoke('file:create-template', path, portCount),
    getRecent: () =>
      ipcRenderer.invoke('file:get-recent'),
    getDefaultTemplates: () =>
      ipcRenderer.invoke('file:get-default-templates'),
    openDefaultTemplate: (name: string) =>
      ipcRenderer.invoke('file:open-default-template', name),
  },

  // Settings
  settings: {
    get: () =>
      ipcRenderer.invoke('settings:get'),
    set: (partial: unknown) =>
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
      const subscription = (_event: unknown, ...args: unknown[]) => callback(...args)
      ipcRenderer.on(channel, subscription)
      return () => { ipcRenderer.removeListener(channel, subscription) }
    }
    return () => {}
  },

  // Remove all listeners for a channel
  removeAllListeners: (channel: string) => {
    ipcRenderer.removeAllListeners(channel)
  },
}

contextBridge.exposeInMainWorld('helix', helixAPI)
