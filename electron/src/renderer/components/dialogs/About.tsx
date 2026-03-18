import React from 'react'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'

export default function About() {
  const { closeDialog } = useUIStore()

  return (
    <DialogWrapper title="About" onClose={closeDialog}>
      <div className="text-center space-y-3 min-w-[300px]">
        <div className="text-4xl mb-2">HLM</div>
        <div className="text-lg font-semibold text-helix-text">Helix Label Manager</div>
        <div className="text-sm text-helix-text-muted">Version 1.0.0</div>
        <div className="text-xs text-helix-text-dim space-y-1">
          <p>Desktop application for managing video router labels.</p>
          <p>Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2.</p>
          <p className="pt-2">Built with Electron + React + TypeScript</p>
          <p>&copy; Solotech</p>
        </div>
        <div className="flex justify-center pt-2">
          <button onClick={closeDialog} className="px-6 py-2 text-sm bg-helix-accent rounded hover:bg-helix-accent-hover text-white">OK</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
