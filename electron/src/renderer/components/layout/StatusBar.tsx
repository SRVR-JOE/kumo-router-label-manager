import React from 'react'
import { useRouterStore } from '../../stores/router-store'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'

export default function StatusBar() {
  const router = useRouterStore()
  const labels = useLabelsStore()
  const ui = useUIStore()

  const statusColor = {
    disconnected: 'bg-gray-500',
    connecting: 'bg-yellow-500 animate-pulse',
    connected: 'bg-green-500',
    error: 'bg-red-500',
  }[router.connectionStatus]

  const changedCount = labels.getChangedLabels().length
  const totalCount = labels.labels.length

  return (
    <div className="h-7 min-h-[28px] bg-helix-surface border-t border-helix-border flex items-center px-3 text-xs text-helix-text-muted gap-4">
      {/* Connection status */}
      <div className="flex items-center gap-1.5">
        <span className={`w-2.5 h-2.5 rounded-full ${statusColor}`} />
        {router.connectionStatus === 'connected' ? (
          <span>{router.deviceName} ({router.ip}) — {router.routerType?.toUpperCase()} {router.inputCount}x{router.outputCount}</span>
        ) : (
          <span>{router.connectionStatus === 'connecting' ? 'Connecting...' : 'Disconnected'}</span>
        )}
      </div>

      {/* Labels info */}
      {totalCount > 0 && (
        <span>Labels: {totalCount} | Changed: {changedCount}</span>
      )}

      {/* File path */}
      {labels.currentFilePath && (
        <span className="truncate max-w-[400px]">{labels.currentFilePath}</span>
      )}

      {/* Progress bar */}
      {ui.progressVisible && (
        <div className="flex items-center gap-2 ml-auto">
          <span>{ui.progressPhase}</span>
          <div className="w-40 h-2 bg-helix-bg rounded-full overflow-hidden">
            <div
              className="h-full bg-helix-accent transition-all duration-200"
              style={{ width: `${ui.progressTotal > 0 ? (ui.progressValue / ui.progressTotal) * 100 : 0}%` }}
            />
          </div>
          <span>{ui.progressValue}/{ui.progressTotal}</span>
        </div>
      )}
    </div>
  )
}
