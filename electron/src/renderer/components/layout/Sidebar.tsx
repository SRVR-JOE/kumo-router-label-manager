import React from 'react'
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
  const { openFile, saveFile, saveFileAs, createTemplate } = useLabels()
  const isConnected = router.connectionStatus === 'connected'
  const hasLabels = labelsStore.labels.length > 0
  const changedCount = labelsStore.getChangedLabels().length

  return (
    <div className="w-[200px] min-w-[200px] bg-helix-surface border-r border-helix-border flex flex-col p-3 gap-2 overflow-y-auto">
      <div className="text-xs font-bold text-helix-text-muted uppercase tracking-wider mb-1">Router</div>
      <SidebarButton
        label={isConnected ? 'Disconnect' : 'Connect...'}
        onClick={() => isConnected ? disconnect() : ui.openDialog('connect')}
        variant={isConnected ? 'danger' : 'primary'}
      />
      <SidebarButton label="Download Labels" onClick={downloadLabels} disabled={!isConnected} variant="success" />
      <SidebarButton label={`Upload (${changedCount})`} onClick={uploadLabels} disabled={!isConnected || changedCount === 0} variant="success" />
      {router.routerType === 'kumo' && (
        <SidebarButton label="Crosspoint Matrix" onClick={() => ui.openDialog('crosspoint')} disabled={!isConnected} />
      )}

      <div className="border-t border-helix-border my-2" />

      <div className="text-xs font-bold text-helix-text-muted uppercase tracking-wider mb-1">File</div>
      <SidebarButton label="Open..." onClick={openFile} />
      <SidebarButton label="Save" onClick={saveFile} disabled={!hasLabels} />
      <SidebarButton label="Save As..." onClick={saveFileAs} disabled={!hasLabels} />
      <SidebarButton label="New Template" onClick={createTemplate} />

      <div className="border-t border-helix-border my-2" />

      <div className="text-xs font-bold text-helix-text-muted uppercase tracking-wider mb-1">Tools</div>
      <SidebarButton label="Find & Replace" onClick={() => ui.openDialog('find-replace')} disabled={!hasLabels} />
      <SidebarButton label="Auto-Number" onClick={() => ui.openDialog('auto-number')} disabled={!hasLabels} />
      <SidebarButton label="Bulk Ops" onClick={() => ui.openDialog('bulk-ops')} disabled={!hasLabels} />
      <SidebarButton label="Statistics" onClick={() => ui.openDialog('statistics')} disabled={!hasLabels} />

      <div className="border-t border-helix-border my-2" />
      <SidebarButton label="Settings" onClick={() => ui.openDialog('settings')} />
      <SidebarButton label="About" onClick={() => ui.openDialog('about')} />
    </div>
  )
}
