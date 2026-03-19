import { useLabelsStore, LabelRow } from '../stores/labels-store'
import { useUIStore } from '../stores/ui-store'

export function useLabels() {
  const store = useLabelsStore()
  const ui = useUIStore()

  const openFile = async () => {
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
    const labels: LabelRow[] = data.ports.map(p => ({
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
    store.setLabels(labels)
    if (data.filePath) store.setFilePath(data.filePath)
    ui.showToast(`Opened file with ${labels.length} labels`, 'success')
  }

  const saveFile = async () => {
    if (!store.currentFilePath) return saveFileAs()
    const portData = store.labels.map(l => ({
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
    await window.helix.file.save(store.currentFilePath, { ports: portData })
    ui.showToast('File saved', 'success')
  }

  const saveFileAs = async () => {
    const portData = store.labels.map(l => ({
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
      store.setFilePath(path)
      ui.showToast(`Saved to ${path}`, 'success')
    }
  }

  const createTemplate = async () => {
    await window.helix.file.createTemplate('', 32)
    ui.showToast('Template created', 'success')
  }

  const loadDefaultTemplate = async (filename: string) => {
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
    const labels: LabelRow[] = data.ports.map(p => ({
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
    store.setLabels(labels)
    store.setFilePath(null) // Template is not a saved file yet
    const size = labels.length / 2
    ui.showToast(`Loaded ${size}x${size} template (${labels.length} ports)`, 'success')
  }

  return { openFile, saveFile, saveFileAs, createTemplate, loadDefaultTemplate }
}
