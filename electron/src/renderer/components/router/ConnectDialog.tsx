import React, { useState } from 'react'
import { useUIStore } from '../../stores/ui-store'
import { useRouter } from '../../hooks/useRouter'

export default function ConnectDialog() {
  const { closeDialog } = useUIStore()
  const { connect } = useRouter()
  const [ip, setIp] = useState('')
  const [routerType, setRouterType] = useState<string>('')
  const [detecting, setDetecting] = useState(false)
  const [detectedType, setDetectedType] = useState<string | null>(null)

  const handleDetect = async () => {
    if (!ip.trim()) return
    setDetecting(true)
    setDetectedType(null)
    const type = await window.helix.router.detectType(ip.trim()) as string | null
    setDetectedType(type)
    if (type) setRouterType(type)
    setDetecting(false)
  }

  const handleConnect = async () => {
    if (!ip.trim()) return
    await connect(ip.trim(), routerType || undefined)
    closeDialog()
  }

  return (
    <DialogWrapper title="Connect to Router" onClose={closeDialog}>
      <div className="space-y-4">
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">IP Address</label>
          <div className="flex gap-2">
            <input
              type="text"
              value={ip}
              onChange={e => setIp(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleConnect()}
              placeholder="192.168.1.100"
              className="flex-1 bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none"
              autoFocus
            />
            <button
              onClick={handleDetect}
              disabled={!ip.trim() || detecting}
              className="px-3 py-2 text-xs bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover disabled:opacity-40 text-helix-text"
            >
              {detecting ? 'Detecting...' : 'Auto-Detect'}
            </button>
          </div>
          {detectedType && (
            <div className="mt-1 text-xs text-green-400">Detected: {detectedType.toUpperCase()}</div>
          )}
          {detectedType === null && detecting === false && ip.trim() && detectedType !== undefined && (
            <div className="mt-1 text-xs text-red-400">No router detected</div>
          )}
        </div>

        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Router Type (optional)</label>
          <select
            value={routerType}
            onChange={e => setRouterType(e.target.value)}
            className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text"
          >
            <option value="">Auto-Detect</option>
            <option value="kumo">AJA KUMO</option>
            <option value="videohub">Blackmagic Videohub</option>
            <option value="lightware">Lightware MX2</option>
          </select>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">
            Cancel
          </button>
          <button onClick={handleConnect} disabled={!ip.trim()} className="px-4 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover disabled:opacity-40 text-white">
            Connect
          </button>
        </div>
      </div>
    </DialogWrapper>
  )
}

// Shared dialog wrapper
export function DialogWrapper({ title, onClose, children, width = 'max-w-md' }: {
  title: string; onClose: () => void; children: React.ReactNode; width?: string
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div className={`bg-helix-surface border border-helix-border rounded-lg shadow-2xl p-5 ${width}`} onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-helix-text">{title}</h2>
          <button onClick={onClose} className="text-helix-text-dim hover:text-helix-text text-lg">&times;</button>
        </div>
        {children}
      </div>
    </div>
  )
}
