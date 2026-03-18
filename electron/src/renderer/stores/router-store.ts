import { create } from 'zustand'

type RouterType = 'kumo' | 'videohub' | 'lightware'
type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error'

interface RouterState {
  ip: string
  routerType: RouterType | null
  deviceName: string
  connectionStatus: ConnectionStatus
  inputCount: number
  outputCount: number
  error: string | null

  setIp: (ip: string) => void
  setConnected: (type: RouterType, name: string, inputs: number, outputs: number) => void
  setDisconnected: () => void
  setConnecting: () => void
  setError: (error: string) => void
  setConnectionStatus: (status: ConnectionStatus) => void
}

export const useRouterStore = create<RouterState>((set) => ({
  ip: '',
  routerType: null,
  deviceName: '',
  connectionStatus: 'disconnected',
  inputCount: 0,
  outputCount: 0,
  error: null,

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
}))
