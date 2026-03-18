import React, { useState } from 'react'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'

export default function AutoNumber() {
  const { closeDialog, showToast } = useUIStore()
  const { autoNumber } = useLabelsStore()
  const [prefix, setPrefix] = useState('Port ')
  const [startNum, setStartNum] = useState(1)
  const [padding, setPadding] = useState(2)
  const [startPort, setStartPort] = useState(1)
  const [endPort, setEndPort] = useState(32)
  const [portType, setPortType] = useState<'INPUT' | 'OUTPUT' | 'ALL'>('ALL')

  const handleApply = () => {
    autoNumber(startPort, endPort, portType, prefix, startNum, padding)
    showToast('Auto-numbering applied', 'success')
    closeDialog()
  }

  return (
    <DialogWrapper title="Auto-Number" onClose={closeDialog}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Prefix</label>
            <input value={prefix} onChange={e => setPrefix(e.target.value)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
          </div>
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Start Number</label>
            <input type="number" value={startNum} onChange={e => setStartNum(parseInt(e.target.value) || 1)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
          </div>
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Zero Padding</label>
            <input type="number" min={0} max={5} value={padding} onChange={e => setPadding(parseInt(e.target.value) || 0)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
          </div>
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Port Type</label>
            <select value={portType} onChange={e => setPortType(e.target.value as typeof portType)} className="w-full bg-helix-bg border border-helix-border rounded px-2 py-2 text-sm text-helix-text">
              <option value="ALL">All</option>
              <option value="INPUT">Inputs Only</option>
              <option value="OUTPUT">Outputs Only</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">Start Port</label>
            <input type="number" min={1} value={startPort} onChange={e => setStartPort(parseInt(e.target.value) || 1)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
          </div>
          <div>
            <label className="block text-xs text-helix-text-muted mb-1">End Port</label>
            <input type="number" min={1} value={endPort} onChange={e => setEndPort(parseInt(e.target.value) || 32)} className="w-full bg-helix-bg border border-helix-border rounded px-3 py-2 text-sm text-helix-text focus:border-helix-accent focus:outline-none" />
          </div>
        </div>
        <div className="text-xs text-helix-text-muted">
          Preview: {prefix}{String(startNum).padStart(padding, '0')}, {prefix}{String(startNum + 1).padStart(padding, '0')}, ...
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Cancel</button>
          <button onClick={handleApply} className="px-4 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover text-white">Apply</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
