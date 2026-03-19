import React, { useEffect } from 'react'
import { useRouterStore } from '../../stores/router-store'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { useRouter } from '../../hooks/useRouter'
import { useLabels } from '../../hooks/useLabels'

function SidebarButton({ label, onClick, disabled, variant = 'default' }: {
  label: string; onClick: () => void; disabled?: boolean; variant?: 'default' | 'primary' | 'success' | 'danger'
}) {
  const colors = {
    default: 'bg-helix-surface hover:bg-helix-surface-hover border-helix-border',
    primary: 'bg-helix-accent hover:bg-helix-accent-hover border-helix-accent',
    success: 'bg-green-700 hover:bg-green-600 border-green-600',
    danger: 'bg-red-800 hover:bg-red-700 border-red-700',
  }
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`w-full py-2 px-3 text-sm rounded border ${colors[variant]} text-helix-text disabled:opacity-40 disabled:cursor-not-allowed transition-colors`}
    >
      {label}
    </button>
  )
}

export default function Sidebar() {
  const router = useRouterStore()
  const labelsStore = useLabelsStore()
  const ui = useUIStore()
  const { connect, disconnect, downloadLabels, uploadLabels } = useRouter()
  const { openFile, saveFile, saveFileAs, createTemplate, loadDefaultTemplate } = useLabels()
  const isConnected = router.connectionStatus === 'connected'
  const hasLabels = labelsStore.labels.length > 0
  const changedCount = labelsStore.getChangedLabels().length

  useEffect(() => {
    router.loadSavedRouters()
  }, [])

  const handleSaveCurrentRouter = async () => {
    if (!isConnected) return
    const name = router.deviceName || router.ip
    await router.addSavedRouter({
      name,
      ip: router.ip,
      routerType: router.routerType || undefined,
    })
    ui.showToast(`Saved "${name}"`, 'success')
  }

  const handleQuickConnect = async (saved: { name: string; ip: string; routerType?: string }) => {
    await connect(saved.ip, saved.routerType)
  }

  return (
    <div className="w-[210px] min-w-[210px] bg-helix-surface border-r border-helix-border flex flex-col p-3 gap-1.5 overflow-y-auto">
      {/* ── Router ── */}
      <div className="text-[11px] font-bold text-helix-text-muted uppercase tracking-wider mb-0.5">Router</div>
      <SidebarButton
        label={isConnected ? 'Disconnect' : 'Connect...'}
        onClick={() => isConnected ? disconnect() : ui.openDialog('connect')}
        variant={isConnected ? 'danger' : 'primary'}
      />
      <SidebarButton label="Download Labels" onClick={downloadLabels} disabled={!isConnected} variant="success" />
      <SidebarButton label={`Upload (${changedCount})`} onClick={uploadLabels} disabled={!isConnected || changedCount === 0} variant="success" />
      <SidebarButton label="Crosspoint Matrix" onClick={() => ui.openDialog('crosspoint')} disabled={!isConnected} />

      {/* ── Quick Connect ── */}
      <div className="border-t border-helix-border my-1.5" />
      <div className="flex items-center justify-between mb-1">
        <div className="text-[11px] font-bold text-helix-text-muted uppercase tracking-wider">Saved Routers</div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => ui.openDialog('scan')}
            title="Scan network for routers"
            className="text-[11px] text-helix-accent hover:text-helix-accent-hover px-1 font-medium"
          >Scan</button>
          {isConnected && (
            <button
              onClick={handleSaveCurrentRouter}
              title="Save current connection"
              className="text-sm text-helix-accent hover:text-helix-accent-hover px-1 font-bold"
            >+</button>
          )}
        </div>
      </div>
      <div className="flex flex-col gap-1.5">
        {router.savedRouters.length === 0 && (
          <div className="text-[10px] text-helix-text-dim italic py-1 px-1">No saved routers</div>
        )}
        {router.savedRouters.map(saved => (
          <div key={saved.ip} className="flex items-center gap-1">
            <button
              onClick={() => handleQuickConnect(saved)}
              disabled={isConnected && router.ip === saved.ip}
              className="flex-1 py-2 px-2.5 text-left rounded border border-helix-border bg-helix-bg hover:bg-helix-surface-hover text-helix-text disabled:opacity-40 transition-colors overflow-hidden"
              title={`${saved.name} (${saved.ip})`}
            >
              <div className="text-[12px] font-semibold truncate leading-tight">{saved.name}</div>
              <div className="text-helix-text-muted text-[10px] leading-tight mt-0.5">{saved.ip}{saved.routerType ? ` · ${saved.routerType.toUpperCase()}` : ''}</div>
            </button>
            <button
              onClick={() => router.removeSavedRouter(saved.ip)}
              className="text-helix-text-dim hover:text-red-400 text-sm px-1 self-center"
              title="Remove"
            >&times;</button>
          </div>
        ))}
      </div>

      {/* ── File ── */}
      <div className="border-t border-helix-border my-1.5" />
      <div className="text-[11px] font-bold text-helix-text-muted uppercase tracking-wider mb-0.5">File</div>
      <SidebarButton label="Open..." onClick={openFile} />
      <SidebarButton label="Save" onClick={saveFile} disabled={!hasLabels} />
      <SidebarButton label="Save As..." onClick={saveFileAs} disabled={!hasLabels} />
      <SidebarButton label="New Template" onClick={createTemplate} />

      {/* ── Tools ── */}
      <div className="border-t border-helix-border my-1.5" />
      <div className="text-[11px] font-bold text-helix-text-muted uppercase tracking-wider mb-0.5">Tools</div>
      <SidebarButton label="Find & Replace" onClick={() => ui.openDialog('find-replace')} disabled={!hasLabels} />
      <SidebarButton label="Auto-Number" onClick={() => ui.openDialog('auto-number')} disabled={!hasLabels} />
      <SidebarButton label="Bulk Ops" onClick={() => ui.openDialog('bulk-ops')} disabled={!hasLabels} />
      <SidebarButton label="Statistics" onClick={() => ui.openDialog('statistics')} disabled={!hasLabels} />

      {/* ── Settings ── */}
      <div className="border-t border-helix-border my-1.5" />
      <SidebarButton label="Settings" onClick={() => ui.openDialog('settings')} />
      <SidebarButton label="About" onClick={() => ui.openDialog('about')} />
    </div>
  )
}
