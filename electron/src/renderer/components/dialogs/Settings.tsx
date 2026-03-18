import React, { useState, useEffect } from 'react'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'

interface AppSettings {
  defaultIp: string
  defaultFilePath: string
  autoConnect: boolean
  maxLabelLength: number
  theme: string
}

export default function Settings() {
  const { closeDialog, showToast } = useUIStore()
  const [settings, setSettings] = useState<AppSettings>({
    defaultIp: '',
    defaultFilePath: '',
    autoConnect: false,
    maxLabelLength: 255,
    theme: 'dark',
  })

  useEffect(() => {
    window.helix.settings.get().then((s: unknown) => {
      setSettings(s as AppSettings)
    })
  }, [])

  const handleSave = async () => {
    await window.helix.settings.set(settings)
    showToast('Settings saved', 'success')
    closeDialog()
  }

  return (
    <DialogWrapper title="Settings" onClose={closeDialog}>
      <div className="space-y-3 min-w-[350px]">
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Default IP Address</label>
          <input
            value={settings.defaultIp}
            onChange={e => setSettings({ ...settings, defaultIp: e.target.value })}
            placeholder="192.168.1.100"
            className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none"
          />
        </div>
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Default File Path</label>
          <input
            value={settings.defaultFilePath}
            onChange={e => setSettings({ ...settings, defaultFilePath: e.target.value })}
            className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none"
          />
        </div>
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Max Label Length</label>
          <input
            type="number"
            min={1}
            max={255}
            value={settings.maxLabelLength}
            onChange={e => setSettings({ ...settings, maxLabelLength: parseInt(e.target.value) || 255 })}
            className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none"
          />
        </div>
        <label className="flex items-center gap-2 text-sm text-helix-text">
          <input
            type="checkbox"
            checked={settings.autoConnect}
            onChange={e => setSettings({ ...settings, autoConnect: e.target.checked })}
          />
          Auto-connect on startup
        </label>
        <div className="flex justify-end gap-2 pt-2">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Cancel</button>
          <button onClick={handleSave} className="px-4 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover text-white">Save</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
