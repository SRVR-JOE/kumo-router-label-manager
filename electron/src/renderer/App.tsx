import React, { useEffect, useMemo } from 'react'
import Sidebar from './components/layout/Sidebar'
import StatusBar from './components/layout/StatusBar'
import LabelTable from './components/labels/LabelTable'
import ConnectDialog from './components/router/ConnectDialog'
import ScanDialog from './components/router/ScanDialog'
import FindReplace from './components/dialogs/FindReplace'
import AutoNumber from './components/dialogs/AutoNumber'
import BulkOps from './components/dialogs/BulkOps'
import Statistics from './components/dialogs/Statistics'
import Settings from './components/dialogs/Settings'
import About from './components/dialogs/About'
import CrosspointMatrix from './components/matrix/CrosspointMatrix'
import ErrorBoundary from './components/ErrorBoundary'
import { useUIStore } from './stores/ui-store'
import { useLabelsStore } from './stores/labels-store'
import { useIpcEvents, useMenuEvents } from './hooks/useIpc'
import { useRouter } from './hooks/useRouter'
import { useLabels } from './hooks/useLabels'

function Toast() {
  const toastMessage = useUIStore(s => s.toastMessage)
  const toastType = useUIStore(s => s.toastType)
  const clearToast = useUIStore(s => s.clearToast)
  useEffect(() => {
    if (toastMessage) {
      const timer = setTimeout(clearToast, 4000)
      return () => clearTimeout(timer)
    }
  }, [toastMessage, clearToast])

  if (!toastMessage) return null
  const colors = {
    success: 'bg-green-800 border-green-600',
    error: 'bg-red-900 border-red-600',
    warning: 'bg-yellow-900 border-yellow-600',
    info: 'bg-helix-surface border-helix-accent',
  }

  return (
    <div className={`fixed top-4 right-4 z-[100] px-4 py-2 rounded-lg border text-sm text-helix-text shadow-lg ${colors[toastType]} animate-slide-in`}>
      {toastMessage}
      <button onClick={clearToast} className="ml-3 text-helix-text-muted hover:text-helix-text">&times;</button>
    </div>
  )
}

export default function App() {
  // Field/action-level selectors: activeDialog is the only piece of ui-store
  // state this component reads, and openDialog/undo/redo are stable zustand
  // action references. This means App no longer re-renders (and menuHandlers
  // below no longer gets recomputed) for unrelated store changes like the
  // label search box's searchText, which lives in labels-store.
  const activeDialog = useUIStore(s => s.activeDialog)
  const openDialog = useUIStore(s => s.openDialog)
  const undo = useLabelsStore(s => s.undo)
  const redo = useLabelsStore(s => s.redo)
  const { disconnect, downloadLabels, uploadLabels } = useRouter()
  const { openFile, saveFile, saveFileAs, createTemplate } = useLabels()

  // Register IPC event listeners
  useIpcEvents()

  // Register menu event handlers
  const menuHandlers = useMemo(() => ({
    'menu:new': () => useLabelsStore.getState().setLabels([]),
    'menu:open': openFile,
    'menu:save': saveFile,
    'menu:save-as': saveFileAs,
    'menu:create-template': createTemplate,
    'menu:connect': () => openDialog('connect'),
    'menu:disconnect': disconnect,
    'menu:download': downloadLabels,
    'menu:upload': uploadLabels,
    'menu:crosspoint': () => openDialog('crosspoint'),
    'menu:find-replace': () => openDialog('find-replace'),
    'menu:auto-number': () => openDialog('auto-number'),
    'menu:bulk-ops': () => openDialog('bulk-ops'),
    'menu:statistics': () => openDialog('statistics'),
    'menu:settings': () => openDialog('settings'),
    'menu:about': () => openDialog('about'),
    'menu:undo': undo,
    'menu:redo': redo,
  }), [openFile, saveFile, saveFileAs, createTemplate, disconnect, downloadLabels, uploadLabels, openDialog, undo, redo])

  useMenuEvents(menuHandlers)

  return (
    <div className="h-screen flex flex-col bg-helix-bg text-helix-text">
      {/* Main content */}
      <div className="flex-1 flex overflow-hidden">
        <Sidebar />
        <div className="flex-1 flex flex-col overflow-hidden">
          <ErrorBoundary label="Label Table" compact>
            <LabelTable />
          </ErrorBoundary>
        </div>
      </div>

      {/* Status bar */}
      <StatusBar />

      {/* Toast notifications */}
      <Toast />

      {/* Dialogs */}
      {activeDialog === 'connect' && <ConnectDialog />}
      {activeDialog === 'scan' && <ScanDialog />}
      {activeDialog === 'find-replace' && <FindReplace />}
      {activeDialog === 'auto-number' && <AutoNumber />}
      {activeDialog === 'bulk-ops' && <BulkOps />}
      {activeDialog === 'statistics' && <Statistics />}
      {activeDialog === 'settings' && <Settings />}
      {activeDialog === 'about' && <About />}
      {activeDialog === 'crosspoint' && <CrosspointMatrix />}
    </div>
  )
}
