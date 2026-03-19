import { create } from 'zustand'

type RouterType = 'kumo' | 'videohub' | 'lightware'
type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error'

export interface SavedRouter {
  name: string
  ip: string
  routerType?: RouterType
}

interface RouterState {
  ip: string
  routerType: RouterType | null
  deviceName: string
  connectionStatus: ConnectionStatus
  inputCount: number
  outputCount: number
  error: string | null
  savedRouters: SavedRouter[]

  setIp: (ip: string) => void
  setConnected: (type: RouterType, name: string, inputs: number, outputs: number) => void
  setDisconnected: () => void
  setConnecting: () => void
  setError: (error: string) => void
  setConnectionStatus: (status: ConnectionStatus) => void
  setSavedRouters: (routers: SavedRouter[]) => void
  loadSavedRouters: () => Promise<void>
  addSavedRouter: (router: SavedRouter) => Promise<void>
  removeSavedRouter: (ip: string) => Promise<void>
}

export const useRouterStore = create<RouterState>((set, get) => ({
  ip: '',
  routerType: null,
  deviceName: '',
  connectionStatus: 'disconnected',
  inputCount: 0,
  outputCount: 0,
  error: null,
  savedRouters: [],

  setIp: (ip) => set({ ip }),
  setConnected: (type, name, inputs, outputs) => set({
    routerType: type,
    deviceName: name,
    connectionStatus: 'connected',
    inputCount: inputs,
    outputCount: outputs,
    error: null,
  }),
  setDisconnected: () => set({
    routerType: null,
    deviceName: '',
    connectionStatus: 'disconnected',
    inputCount: 0,
    outputCount: 0,
    error: null,
  }),
  setConnecting: () => set({ connectionStatus: 'connecting', error: null }),
  setError: (error) => set({ connectionStatus: 'error', error }),
  setConnectionStatus: (status) => set({ connectionStatus: status }),
  setSavedRouters: (routers) => set({ savedRouters: routers }),
  loadSavedRouters: async () => {
    const settings = await window.helix.settings.get() as { savedRouters?: SavedRouter[] }
    set({ savedRouters: settings.savedRouters || [] })
  },
  addSavedRouter: async (router) => {
    const current = get().savedRouters
    const updated = [...current.filter(r => r.ip !== router.ip), router]
    set({ savedRouters: updated })
    await window.helix.settings.set({ savedRouters: updated })
  },
  removeSavedRouter: async (ip) => {
    const updated = get().savedRouters.filter(r => r.ip !== ip)
    set({ savedRouters: updated })
    await window.helix.settings.set({ savedRouters: updated })
  },
}))
