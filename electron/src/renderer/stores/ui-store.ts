import { create } from 'zustand'

type DialogType = 'connect' | 'find-replace' | 'auto-number' | 'bulk-ops' | 'statistics' | 'settings' | 'about' | 'crosspoint' | null

interface UIState {
  activeDialog: DialogType
  activeTab: 'labels' | 'crosspoint'
  progressVisible: boolean
  progressValue: number
  progressTotal: number
  progressPhase: string
  toastMessage: string | null
  toastType: 'success' | 'error' | 'warning' | 'info'

  openDialog: (dialog: DialogType) => void
  closeDialog: () => void
  setTab: (tab: 'labels' | 'crosspoint') => void
  showProgress: (value: number, total: number, phase: string) => void
  hideProgress: () => void
  showToast: (message: string, type?: 'success' | 'error' | 'warning' | 'info') => void
  clearToast: () => void
}

export const useUIStore = create<UIState>((set) => ({
  activeDialog: null,
  activeTab: 'labels',
  progressVisible: false,
  progressValue: 0,
  progressTotal: 0,
  progressPhase: '',
  toastMessage: null,
  toastType: 'info',

  openDialog: (dialog) => set({ activeDialog: dialog }),
  closeDialog: () => set({ activeDialog: null }),
  setTab: (tab) => set({ activeTab: tab }),
  showProgress: (value, total, phase) => set({ progressVisible: true, progressValue: value, progressTotal: total, progressPhase: phase }),
  hideProgress: () => set({ progressVisible: false, progressValue: 0, progressTotal: 0, progressPhase: '' }),
  showToast: (message, type = 'info') => set({ toastMessage: message, toastType: type }),
  clearToast: () => set({ toastMessage: null }),
}))
