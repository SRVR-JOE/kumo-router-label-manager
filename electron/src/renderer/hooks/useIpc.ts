import { useEffect, useRef } from 'react'
import { useRouterStore } from '../stores/router-store'
import { useUIStore } from '../stores/ui-store'

export function useIpcEvents(): void {
  const setConnectionStatus = useRouterStore(s => s.setConnectionStatus)
  // Field-level selectors instead of a whole-store destructure — these are
  // stable zustand action references, so this hook's effect below never
  // needs to re-run once mounted.
  const showProgress = useUIStore(s => s.showProgress)
  const hideProgress = useUIStore(s => s.hideProgress)
  const showToast = useUIStore(s => s.showToast)

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
  // `handlers` is expected to be memoized by the caller, but it can still end
  // up with a new identity on renders that are unrelated to the menu wiring
  // itself — e.g. if any handler closes over a value that changes often, or
  // over a hook this file doesn't control. To make the actual Electron IPC
  // subscriptions immune to that churn, we only ever attach/detach listeners
  // once per distinct set of channel names (which is static — it mirrors the
  // app's fixed menu structure) and always dispatch through a ref holding the
  // latest handlers. This guarantees we never tear down and re-register the
  // ~17 menu listeners just because a handler closure was recreated.
  const handlersRef = useRef(handlers)
  useEffect(() => {
    handlersRef.current = handlers
  })

  const channelsKey = Object.keys(handlers).sort().join('|')

  useEffect(() => {
    const unsubs: (() => void)[] = []
    for (const channel of Object.keys(handlersRef.current)) {
      unsubs.push(window.helix.on(channel, () => {
        handlersRef.current[channel]?.()
      }))
    }
    return () => { unsubs.forEach(fn => fn()) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [channelsKey])
}
