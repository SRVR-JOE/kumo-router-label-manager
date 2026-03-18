import React, { useState } from 'react'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'

export default function FindReplace() {
  const { closeDialog, showToast } = useUIStore()
  const { findReplace } = useLabelsStore()
  const [find, setFind] = useState('')
  const [replace, setReplace] = useState('')
  const [field, setField] = useState<'newLabel' | 'newLabelLine2'>('newLabel')
  const [caseSensitive, setCaseSensitive] = useState(false)

  const handleReplace = () => {
    if (!find) return
    const count = findReplace(find, replace, field, caseSensitive)
    showToast(`Replaced ${count} occurrence${count !== 1 ? 's' : ''}`, 'success')
  }

  return (
    <DialogWrapper title="Find & Replace" onClose={closeDialog}>
      <div className="space-y-3">
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Find</label>
          <input value={find} onChange={e => setFind(e.target.value)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" autoFocus />
        </div>
        <div>
          <label className="block text-xs text-helix-text-muted mb-1">Replace with</label>
          <input value={replace} onChange={e => setReplace(e.target.value)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
        </div>
        <div className="flex gap-4">
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Field</label>
            <select value={field} onChange={e => setField(e.target.value as typeof field)} className="bg-helix-bg border border-helix-border rounded px-2 py-1 text-sm text-helix-text">
              <option value="newLabel">New Label</option>
              <option value="newLabelLine2">New Label Line 2</option>
            </select>
          </div>
          <label className="flex items-center gap-2 text-xs text-helix-text-muted mt-4">
            <input type="checkbox" checked={caseSensitive} onChange={e => setCaseSensitive(e.target.checked)} />
            Case sensitive
          </label>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Close</button>
          <button onClick={handleReplace} disabled={!find} className="px-4 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover disabled:opacity-40 text-white">Replace All</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
