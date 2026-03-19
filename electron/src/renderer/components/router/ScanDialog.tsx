import React, { useState, useEffect, useRef } from 'react'
import { useUIStore } from '../../stores/ui-store'
import { useRouterStore } from '../../stores/router-store'
import { DialogWrapper } from './ConnectDialog'

interface DiscoveredRouter {
  ip: string
  routerType: 'kumo' | 'videohub' | 'lightware'
  deviceName: string
}

interface ScanProgress {
  scanned: number
  total: number
  found: DiscoveredRouter[]
}

const ROUTER_BADGES: Record<string, { label: string; color: string }> = {
  kumo: { label: 'KUMO', color: 'bg-orange-700 text-orange-100' },
  videohub: { label: 'Videohub', color: 'bg-blue-700 text-blue-100' },
  lightware: { label: 'Lightware', color: 'bg-purple-700 text-purple-100' },
}

export default function ScanDialog() {
  const { closeDialog } = useUIStore()
  const { addSavedRouter, savedRouters } = useRouterStore()
  const { showToast } = useUIStore()

  const [subnet, setSubnet] = useState('192.168.100')
  const [scanning, setScanning] = useState(false)
  const [scanned, setScanned] = useState(0)
  const [total, setTotal] = useState(254)
  const [results, setResults] = useState<DiscoveredRouter[]>([])
  const [addedIps, setAddedIps] = useState<Set<string>>(new Set())
  const cleanupRef = useRef<(() => void) | null>(null)

  // Load default subnet from settings
  useEffect(() => {
    window.helix.settings.get().then((s: unknown) => {
      const settings = s as { defaultIp?: string }
      if (settings.defaultIp) {
        // Extract subnet from default IP, e.g. "192.168.100.52" -> "192.168.100"
        const parts = settings.defaultIp.split('.')
        if (parts.length === 4) {
          setSubnet(parts.slice(0, 3).join('.'))
        }
      }
    })
  }, [])

  // Track which IPs are already saved
  useEffect(() => {
    const saved = new Set(savedRouters.map((r) => r.ip))
    setAddedIps(saved)
  }, [savedRouters])

  // Clean up listener on unmount
  useEffect(() => {
    return () => {
      if (cleanupRef.current) cleanupRef.current()
    }
  }, [])

  const handleScan = async () => {
    if (!subnet.trim()) return

    setScanning(true)
    setScanned(0)
    setTotal(254)
    setResults([])

    // Listen for progress events
    const unsub = window.helix.on('scan-progress', (progress: unknown) => {
      const p = progress as ScanProgress
      setScanned(p.scanned)
      setTotal(p.total)
      setResults(p.found)
    })
    cleanupRef.current = unsub

    try {
      const finalResults = (await window.helix.router.scanSubnet(subnet.trim())) as DiscoveredRouter[]
      setResults(finalResults)
    } finally {
      setScanning(false)
      if (unsub) unsub()
      cleanupRef.current = null
    }
  }

  const handleAddRouter = async (router: DiscoveredRouter) => {
    await addSavedRouter({
      name: router.deviceName,
      ip: router.ip,
      routerType: router.routerType,
    })
    setAddedIps((prev) => new Set([...prev, router.ip]))
    showToast(`Added "${router.deviceName}"`, 'success')
  }

  const handleAddAll = async () => {
    let count = 0
    for (const router of results) {
      if (!addedIps.has(router.ip)) {
        await addSavedRouter({
          name: router.deviceName,
          ip: router.ip,
          routerType: router.routerType,
        })
        count++
      }
    }
    setAddedIps((prev) => new Set([...prev, ...results.map((r) => r.ip)]))
    showToast(`Added ${count} router${count !== 1 ? 's' : ''} to Quick Connect`, 'success')
  }

  const unadded = results.filter((r) => !addedIps.has(r.ip))
  const progressPct = total > 0 ? Math.round((scanned / total) * 100) : 0

  return (
    <DialogWrapper title="Scan Network" onClose={closeDialog} width="max-w-lg">
      <div className="space-y-4">
        {/* Subnet input */}
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Subnet Base</label>
          <div className="flex gap-2">
            <div className="flex items-center flex-1">
              <input
                type="text"
                value={subnet}
                onChange={(e) => setSubnet(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && !scanning && handleScan()}
                placeholder="192.168.100"
                disabled={scanning}
                className="flex-1 bg-helix-bg border border-helix-border rounded-l px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none disabled:opacity-60"
                autoFocus
              />
              <span className="bg-helix-bg border border-l-0 border-helix-border rounded-r px-2 py-2 text-sm text-helix-text-muted">
                .1 - .254
              </span>
            </div>
            <button
              onClick={handleScan}
              disabled={!subnet.trim() || scanning}
              className="px-4 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover disabled:opacity-40 text-white whitespace-nowrap"
            >
              {scanning ? 'Scanning...' : 'Scan'}
            </button>
          </div>
        </div>

        {/* Progress bar */}
        {scanning && (
          <div>
            <div className="flex justify-between text-xs text-helix-text-muted mb-1">
              <span>Scanning {subnet}.* ...</span>
              <span>
                {scanned}/{total} ({progressPct}%)
              </span>
            </div>
            <div className="w-full h-2 bg-helix-bg rounded overflow-hidden">
              <div
                className="h-full bg-helix-accent transition-all duration-300 ease-out"
                style={{ width: `${progressPct}%` }}
              />
            </div>
          </div>
        )}

        {/* Results */}
        {results.length > 0 && (
          <div>
            <div className="flex items-center justify-between mb-2">
              <div className="text-xs font-bold text-helix-text-muted uppercase tracking-wider">
                Found {results.length} Router{results.length !== 1 ? 's' : ''}
              </div>
              {unadded.length > 0 && (
                <button
                  onClick={handleAddAll}
                  className="text-xs px-2 py-1 bg-helix-accent rounded hover:bg-helix-accent-hover text-white"
                >
                  Add All ({unadded.length})
                </button>
              )}
            </div>
            <div className="max-h-80 overflow-y-auto space-y-1">
              {results.map((router) => {
                const badge = ROUTER_BADGES[router.routerType]
                const alreadyAdded = addedIps.has(router.ip)
                return (
                  <div
                    key={router.ip}
                    className="flex items-center gap-2 py-2 px-3 rounded border border-helix-border bg-helix-bg"
                  >
                    <span
                      className={`text-[11px] font-bold uppercase px-1.5 py-0.5 rounded ${badge.color}`}
                    >
                      {badge.label}
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm text-helix-text truncate">{router.deviceName}</div>
                      <div className="text-[10px] text-helix-text-muted">{router.ip}</div>
                    </div>
                    <button
                      onClick={() => handleAddRouter(router)}
                      disabled={alreadyAdded}
                      className="text-xs px-2 py-1 rounded border border-helix-border bg-helix-surface hover:bg-helix-surface-hover text-helix-text disabled:opacity-40 disabled:cursor-not-allowed whitespace-nowrap"
                    >
                      {alreadyAdded ? 'Added' : 'Add'}
                    </button>
                  </div>
                )
              })}
            </div>
          </div>
        )}

        {/* No results message */}
        {!scanning && scanned > 0 && results.length === 0 && (
          <div className="text-center py-4 text-sm text-helix-text-muted">
            No routers found on {subnet}.*
          </div>
        )}

        {/* Footer */}
        <div className="flex justify-end pt-2">
          <button
            onClick={closeDialog}
            className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text"
          >
            Close
          </button>
        </div>
      </div>
    </DialogWrapper>
  )
}
