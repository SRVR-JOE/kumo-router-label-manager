import { useRouterStore } from '../stores/router-store'
import { useLabelsStore, LabelRow } from '../stores/labels-store'
import { useUIStore } from '../stores/ui-store'

export function useRouter() {
  const router = useRouterStore()
  const labelsStore = useLabelsStore()
  const ui = useUIStore()

  const connect = async (ip: string, routerType?: string) => {
    router.setIp(ip)
    router.setConnecting()
    const result = await window.helix.router.connect(ip, routerType)
    if (result.success) {
      router.setConnected(result.routerType, result.deviceName, result.inputCount, result.outputCount)
      ui.showToast(`Connected to ${result.deviceName}`, 'success')
      // Auto-download labels after successful connect
      try {
        const rawLabels = await window.helix.router.download() as Array<{
          portNumber: number; portType: 'INPUT' | 'OUTPUT'
          currentLabel: string; newLabel: string | null
          currentLabelLine2: string; newLabelLine2: string | null
          currentColor: number; newColor: number | null; notes: string
        }>
        const labels: LabelRow[] = rawLabels.map(l => ({
          id: `${l.portType}-${l.portNumber}`,
          portNumber: l.portNumber,
          portType: l.portType,
          currentLabel: l.currentLabel,
          newLabel: l.newLabel || '',
          currentLabelLine2: l.currentLabelLine2 || '',
          newLabelLine2: l.newLabelLine2 || '',
          currentColor: l.currentColor,
          newColor: l.newColor,
          notes: l.notes || '',
          status: 'unchanged' as const,
        }))
        labelsStore.setLabels(labels)
        ui.showToast(`Downloaded ${labels.length} labels`, 'success')
      } catch {
        ui.showToast('Auto-download labels failed', 'warning')
      }
    } else {
      router.setError(result.error || 'Connection failed')
      ui.showToast(result.error || 'Connection failed', 'error')
    }
    return result
  }

  const disconnect = async () => {
    await window.helix.router.disconnect()
    router.setDisconnected()
    ui.showToast('Disconnected', 'info')
  }

  const downloadLabels = async () => {
    if (router.connectionStatus !== 'connected') {
      ui.showToast('Not connected to a router', 'warning')
      return
    }
    const rawLabels = await window.helix.router.download() as Array<{
      portNumber: number; portType: 'INPUT' | 'OUTPUT'
      currentLabel: string; newLabel: string | null
      currentLabelLine2: string; newLabelLine2: string | null
      currentColor: number; newColor: number | null; notes: string
    }>
    const labels: LabelRow[] = rawLabels.map(l => ({
      id: `${l.portType}-${l.portNumber}`,
      portNumber: l.portNumber,
      portType: l.portType,
      currentLabel: l.currentLabel,
      newLabel: l.newLabel || '',
      currentLabelLine2: l.currentLabelLine2 || '',
      newLabelLine2: l.newLabelLine2 || '',
      currentColor: l.currentColor,
      newColor: l.newColor,
      notes: l.notes || '',
      status: 'unchanged' as const,
    }))
    labelsStore.setLabels(labels)
    ui.showToast(`Downloaded ${labels.length} labels`, 'success')
  }

  const uploadLabels = async () => {
    const changed = labelsStore.getChangedLabels()
    if (changed.length === 0) {
      ui.showToast('No changes to upload', 'warning')
      return
    }
    const uploadData = changed.map(l => ({
      portNumber: l.portNumber,
      portType: l.portType,
      currentLabel: l.currentLabel,
      newLabel: l.newLabel || null,
      currentLabelLine2: l.currentLabelLine2,
      newLabelLine2: l.newLabelLine2 || null,
      currentColor: l.currentColor,
      newColor: l.newColor,
      notes: l.notes,
    }))
    const result = await window.helix.router.upload(uploadData) as { successCount: number; errorCount: number; errors: string[] }
    if (result.successCount > 0) {
      labelsStore.markUploaded(changed.map(l => l.id))
      ui.showToast(`Uploaded ${result.successCount} labels` + (result.errorCount > 0 ? `, ${result.errorCount} errors` : ''), result.errorCount > 0 ? 'warning' : 'success')
    } else {
      ui.showToast(`Upload failed: ${result.errors.join(', ')}`, 'error')
    }
  }

  return { connect, disconnect, downloadLabels, uploadLabels }
}
