import { useRouterStore } from '../stores/router-store'
import { useLabelsStore, LabelRow } from '../stores/labels-store'
import { useUIStore } from '../stores/ui-store'
import type { RouterType } from '../../main/protocols/types'

export function useRouter() {
  const router = useRouterStore()
  const labelsStore = useLabelsStore()
  const ui = useUIStore()

  const connect = async (ip: string, routerType?: RouterType) => {
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
        labelsStore.setLabels(labels, { kind: 'router', ip })
        ui.showToast(`Downloaded ${labels.length} labels`, 'success')
      } catch {
        // Deliberately leave any previously loaded labels in place rather than
        // discarding the user's work. They stay pinned to their original source,
        // so uploadLabels() will refuse to push them to this newly-connected
        // device until they are re-downloaded or explicitly reloaded.
        ui.showToast('Auto-download labels failed — loaded labels are not from this router', 'warning')
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
    labelsStore.setLabels(labels, { kind: 'router', ip: router.ip })
    ui.showToast(`Downloaded ${labels.length} labels`, 'success')
  }

  const uploadLabels = async () => {
    if (router.connectionStatus !== 'connected') {
      ui.showToast('Not connected to a router', 'warning')
      return
    }
    // Refuse to push a label set downloaded from one router into a different one.
    // File-loaded sets (source null/'file') are not device-specific and are allowed.
    const source = labelsStore.source
    if (source?.kind === 'router' && source.ip !== router.ip) {
      ui.showToast(
        `Upload blocked: these labels were downloaded from ${source.ip}, but you are connected to ${router.ip}. Download from this router first.`,
        'error'
      )
      return
    }
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
    if (result.errorCount === 0 && result.successCount > 0) {
      // Only clear the pending edits when every port was confirmed written.
      labelsStore.markUploaded(changed.map(l => l.id))
      ui.showToast(`Uploaded ${result.successCount} labels`, 'success')
    } else if (result.successCount > 0) {
      // Partial write. The upload result carries no per-port detail, so we cannot
      // tell which ports landed — leave ALL rows pending rather than showing a
      // clean grid over a router that is only partly correct.
      ui.showToast(
        `Partial upload: ${result.successCount} of ${changed.length} labels written, ${result.errorCount} failed. ` +
        `Changes kept pending — re-upload to retry. ${result.errors.join(', ')}`,
        'warning'
      )
    } else {
      ui.showToast(`Upload failed: ${result.errors.join(', ')}`, 'error')
    }
  }

  return { connect, disconnect, downloadLabels, uploadLabels }
}
