import React, { useState } from 'react'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'

export default function BulkOps() {
  const { closeDialog, showToast } = useUIStore()
  const { clearNewLabels, copyCurrentToNew, applyPrefix, applySuffix } = useLabelsStore()
  const [prefix, setPrefix] = useState('')
  const [suffix, setSuffix] = useState('')

  return (
    <DialogWrapper title="Bulk Operations" onClose={closeDialog}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-2">
          <button onClick={() => { copyCurrentToNew(); showToast('Copied current to new', 'success') }} className="px-3 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">
            Copy Current &rarr; New
          </button>
          <button onClick={() => { clearNewLabels(); showToast('Cleared all new labels', 'success') }} className="px-3 py-2 text-sm bg-red-900/50 border border-red-800 rounded hover:bg-red-900 text-helix-text">
            Clear All New
          </button>
        </div>

        <div className="border-t border-helix-border pt-3">
          <div className="flex gap-2 items-end">
            <div className="flex-1">
              <label className="block text-xs text-helix-text-muted mb-1">Prefix</label>
              <input value={prefix} onChange={e => setPrefix(e.target.value)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
            </div>
            <button onClick={() => { if (prefix) { applyPrefix(prefix, 'newLabel'); showToast(`Applied prefix "${prefix}"`, 'success') }}} disabled={!prefix} className="px-3 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover disabled:opacity-40 text-white">
              Apply
            </button>
          </div>
        </div>

        <div>
          <div className="flex gap-2 items-end">
            <div className="flex-1">
              <label className="block text-xs text-helix-text-muted mb-1">Suffix</label>
              <input value={suffix} onChange={e => setSuffix(e.target.value)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
            </div>
            <button onClick={() => { if (suffix) { applySuffix(suffix, 'newLabel'); showToast(`Applied suffix "${suffix}"`, 'success') }}} disabled={!suffix} className="px-3 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover disabled:opacity-40 text-white">
              Apply
            </button>
          </div>
        </div>

        <div className="flex justify-end pt-2">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Close</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
