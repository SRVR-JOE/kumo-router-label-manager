import { useCallback } from 'react'
import { useLabelsStore, LabelRow } from '../stores/labels-store'
import { useUIStore } from '../stores/ui-store'

export function useLabels() {
  // Field-level selectors so this hook (and anything that calls it, e.g.
  // App.tsx's menuHandlers useMemo) only reacts to the specific slices of
  // state each callback actually needs — not the whole store object. Zustand
  // action references (setLabels, setFilePath, showToast) are stable across
  // the store's lifetime, so selecting them directly never causes churn.
  const labels = useLabelsStore(s => s.labels)
  const currentFilePath = useLabelsStore(s => s.currentFilePath)
  const setLabels = useLabelsStore(s => s.setLabels)
  const setFilePath = useLabelsStore(s => s.setFilePath)
  const showToast = useUIStore(s => s.showToast)

  const openFile = useCallback(async () => {
    const data = await window.helix.file.open() as {
      ports: Array<{
        port: number; type: 'INPUT' | 'OUTPUT'
        currentLabel: string; newLabel: string | null
        currentLabelLine2: string; newLabelLine2: string | null
        currentColor: number; newColor: number | null; notes: string
      }>
      filePath?: string
    } | null

    if (!data) return
    const rows: LabelRow[] = data.ports.map(p => ({
      id: `${p.type}-${p.port}`,
      portNumber: p.port,
      portType: p.type,
      currentLabel: p.currentLabel,
      newLabel: p.newLabel || '',
      currentLabelLine2: p.currentLabelLine2 || '',
      newLabelLine2: p.newLabelLine2 || '',
      currentColor: p.currentColor,
      newColor: p.newColor,
      notes: p.notes || '',
      status: 'unchanged' as const,
    }))
    setLabels(rows)
    if (data.filePath) setFilePath(data.filePath)
    showToast(`Opened file with ${rows.length} labels`, 'success')
  }, [setLabels, setFilePath, showToast])

  const saveFileAs = useCallback(async () => {
    const portData = labels.map(l => ({
      port: l.portNumber,
      type: l.portType,
      currentLabel: l.currentLabel,
      newLabel: l.newLabel || null,
      currentLabelLine2: l.currentLabelLine2,
      newLabelLine2: l.newLabelLine2 || null,
      currentColor: l.currentColor,
      newColor: l.newColor,
      notes: l.notes,
    }))
    const path = await window.helix.file.saveAs({ ports: portData }) as string | null
    if (path) {
      setFilePath(path)
      showToast(`Saved to ${path}`, 'success')
    }
  }, [labels, setFilePath, showToast])

  const saveFile = useCallback(async () => {
    if (!currentFilePath) return saveFileAs()
    const portData = labels.map(l => ({
      port: l.portNumber,
      type: l.portType,
      currentLabel: l.currentLabel,
      newLabel: l.newLabel || null,
      currentLabelLine2: l.currentLabelLine2,
      newLabelLine2: l.newLabelLine2 || null,
      currentColor: l.currentColor,
      newColor: l.newColor,
      notes: l.notes,
    }))
    await window.helix.file.save(currentFilePath, { ports: portData })
    showToast('File saved', 'success')
  }, [currentFilePath, labels, saveFileAs, showToast])

  const createTemplate = useCallback(async () => {
    await window.helix.file.createTemplate('', 32)
    showToast('Template created', 'success')
  }, [showToast])

  const loadDefaultTemplate = useCallback(async (filename: string) => {
    const data = await window.helix.file.openDefaultTemplate(filename) as {
      ports: Array<{
        port: number; type: 'INPUT' | 'OUTPUT'
        currentLabel: string; newLabel: string | null
        currentLabelLine2: string; newLabelLine2: string | null
        currentColor: number; newColor: number | null; notes: string
      }>
      filePath?: string
    } | null

    if (!data) return
    const rows: LabelRow[] = data.ports.map(p => ({
      id: `${p.type}-${p.port}`,
      portNumber: p.port,
      portType: p.type,
      currentLabel: p.currentLabel,
      newLabel: p.newLabel || '',
      currentLabelLine2: p.currentLabelLine2 || '',
      newLabelLine2: p.newLabelLine2 || '',
      currentColor: p.currentColor,
      newColor: p.newColor,
      notes: p.notes || '',
      status: 'unchanged' as const,
    }))
    setLabels(rows)
    setFilePath(null) // Template is not a saved file yet
    const size = rows.length / 2
    showToast(`Loaded ${size}x${size} template (${rows.length} ports)`, 'success')
  }, [setLabels, setFilePath, showToast])

  return { openFile, saveFile, saveFileAs, createTemplate, loadDefaultTemplate }
}
