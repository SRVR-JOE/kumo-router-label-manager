import Store from 'electron-store'
import { AppSettings, DEFAULT_SETTINGS } from './protocols/types'

const store = new Store<AppSettings>({
  name: 'helix-settings',
  defaults: DEFAULT_SETTINGS,
})

export function getSettings(): AppSettings {
  return {
    defaultIp: store.get('defaultIp', DEFAULT_SETTINGS.defaultIp),
    defaultFilePath: store.get('defaultFilePath', DEFAULT_SETTINGS.defaultFilePath),
    autoConnect: store.get('autoConnect', DEFAULT_SETTINGS.autoConnect),
    maxLabelLength: store.get('maxLabelLength', DEFAULT_SETTINGS.maxLabelLength),
    recentFiles: store.get('recentFiles', DEFAULT_SETTINGS.recentFiles),
    theme: store.get('theme', DEFAULT_SETTINGS.theme),
    windowBounds: store.get('windowBounds') as AppSettings['windowBounds'],
    savedRouters: store.get('savedRouters', DEFAULT_SETTINGS.savedRouters),
  }
}

export function setSettings(partial: Partial<AppSettings>): void {
  for (const [key, value] of Object.entries(partial)) {
    store.set(key as keyof AppSettings, value)
  }
}

export function addRecentFile(filePath: string): void {
  const recent = store.get('recentFiles', []) as string[]
  const filtered = recent.filter(f => f !== filePath)
  filtered.unshift(filePath)
  store.set('recentFiles', filtered.slice(0, 10))
}

export function getRecentFiles(): string[] {
  return store.get('recentFiles', []) as string[]
}

export function saveWindowBounds(bounds: { x: number; y: number; width: number; height: number }): void {
  store.set('windowBounds', bounds)
}
