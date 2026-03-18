import { useEffect } from 'react'
import { useRouterStore } from '../stores/router-store'
import { useUIStore } from '../stores/ui-store'

export function useIpcEvents(): void {
  const setConnectionStatus = useRouterStore(s => s.setConnectionStatus)
  const { showProgress, hideProgress, showToast } = useUIStore()

  useEffect(() => {
    const unsubs: (() => void)[] = []

    unsubs.push(window.helix.on('connection-status', (status: unknown) => {
      setConnectionStatus(status as 'disconnected' | 'connecting' | 'connected' | 'error')
    }))

    unsubs.push(window.helix.on('progress', (data: unknown) => {
      const d = data as { done: number; total: number; phase: string }
      showProgress(d.done, d.total, d.phase)
      if (d.done >= d.total) {
        setTimeout(hideProgress, 500)
      }
    }))

    unsubs.push(window.helix.on('error', (msg: unknown) => {
      showToast(String(msg), 'error')
    }))

    return () => { unsubs.forEach(fn => fn()) }
  }, [setConnectionStatus, showProgress, hideProgress, showToast])
}

export function useMenuEvents(handlers: Record<string, () => void>): void {
  useEffect(() => {
    const unsubs: (() => void)[] = []
    for (const [channel, handler] of Object.entries(handlers)) {
      unsubs.push(window.helix.on(channel, handler))
    }
    return () => { unsubs.forEach(fn => fn()) }
  }, [handlers])
}
