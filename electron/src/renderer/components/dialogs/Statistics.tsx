import React from 'react'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'
import { KUMO_COLORS } from '../../theme/colors'

export default function Statistics() {
  const { closeDialog } = useUIStore()
  const { labels } = useLabelsStore()

  const inputs = labels.filter(l => l.portType === 'INPUT')
  const outputs = labels.filter(l => l.portType === 'OUTPUT')
  const changed = labels.filter(l => l.status === 'modified')
  const uploaded = labels.filter(l => l.status === 'uploaded')

  // Color distribution
  const colorCounts: Record<number, number> = {}
  for (const l of labels) {
    const c = l.newColor ?? l.currentColor
    colorCounts[c] = (colorCounts[c] || 0) + 1
  }

  return (
    <DialogWrapper title="Statistics" onClose={closeDialog}>
      <div className="space-y-4 min-w-[300px]">
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div className="bg-helix-bg rounded p-3">
            <div className="text-helix-text-muted text-xs">Total Ports</div>
            <div className="text-2xl font-bold text-helix-text">{labels.length}</div>
          </div>
          <div className="bg-helix-bg rounded p-3">
            <div className="text-helix-text-muted text-xs">Changed</div>
            <div className="text-2xl font-bold text-yellow-400">{changed.length}</div>
          </div>
          <div className="bg-helix-bg rounded p-3">
            <div className="text-helix-text-muted text-xs">Inputs</div>
            <div className="text-2xl font-bold text-blue-400">{inputs.length}</div>
          </div>
          <div className="bg-helix-bg rounded p-3">
            <div className="text-helix-text-muted text-xs">Outputs</div>
            <div className="text-2xl font-bold text-orange-400">{outputs.length}</div>
          </div>
          <div className="bg-helix-bg rounded p-3">
            <div className="text-helix-text-muted text-xs">Uploaded</div>
            <div className="text-2xl font-bold text-green-400">{uploaded.length}</div>
          </div>
        </div>

        {Object.keys(colorCounts).length > 0 && (
          <div>
            <div className="text-xs text-helix-text-muted mb-2">Color Distribution</div>
            <div className="space-y-1">
              {Object.entries(colorCounts).sort(([a], [b]) => Number(a) - Number(b)).map(([colorId, count]) => {
                const c = KUMO_COLORS[Number(colorId)]
                if (!c) return null
                const pct = labels.length > 0 ? (count / labels.length) * 100 : 0
                return (
                  <div key={colorId} className="flex items-center gap-2 text-xs">
                    <span className="color-badge" style={{ backgroundColor: c.active }} />
                    <span className="w-24 text-helix-text">{c.name}</span>
                    <div className="flex-1 h-3 bg-helix-bg rounded-full overflow-hidden">
                      <div className="h-full rounded-full" style={{ width: `${pct}%`, backgroundColor: c.active }} />
                    </div>
                    <span className="text-helix-text-muted w-10 text-right">{count}</span>
                  </div>
                )
              })}
            </div>
          </div>
        )}

        <div className="flex justify-end">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Close</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
