// Unified router facade — dispatches to the correct protocol
//
// Owns a single `session` object (rather than a set of loose `let`s) so the
// app has one authoritative, explicit answer to "are we actually still
// talking to a router?" — including after a switch reboot / cable pull that
// the old module-level currentIp/currentType could never detect on its own.

import { RouterType, ConnectionStatus, Label, ConnectResult, UploadResult, Crosspoint, VideohubStatus } from './types'
import { detectRouterType } from './auto-detect'
import { kumoConnect, kumoDownloadLabels, kumoUploadLabels, kumoGetCrosspoints, kumoSetRoute, kumoProbeSystemName } from './kumo-rest'
import { videohubConnect, videohubDownloadLabels, videohubUploadLabels, videohubGetRouting, videohubSetRoute, videohubProbe, videohubGetStatus } from './videohub'
import { lightwareConnect, lightwareDownloadLabels, lightwareUploadLabels, lightwareGetRouting, lightwareSetRoute, lightwareProbe } from './lightware'

// Reuses the renderer-facing ConnectionStatus union so the existing
// 'connection-status' IPC channel (see ipc-handlers.ts) needs no new values:
//   'disconnected' — never connected, or the user explicitly disconnected
//   'connecting'   — connect() in flight (set by ipc-handlers, not here)
//   'connected'    — connected and either just verified, or not yet checked
//   'error'        — was connected, but a liveness probe or operation just
//                    proved the router is unreachable; operations refuse to
//                    run until an explicit reconnect (or the keepalive
//                    observes the router come back and auto-recovers)
type SessionState = ConnectionStatus

interface RouterSession {
  ip: string
  routerType: RouterType | null
  inputCount: number
  outputCount: number
  state: SessionState
  lastSeenAt: number
  lastError?: string
}

function emptySession(): RouterSession {
  return { ip: '', routerType: null, inputCount: 0, outputCount: 0, state: 'disconnected', lastSeenAt: 0 }
}

let session: RouterSession = emptySession()

// --- Keepalive / liveness -------------------------------------------------
//
// None of our protocol adapters hold a socket open between calls (each
// download/upload/etc. opens its own short-lived connection), so there is no
// device-side idle timeout to defend against. The timer's only job is to
// detect a dead router while the app is otherwise idle, so the UI reflects
// reality within ~25-50s instead of only discovering it the next time the
// tech clicks something and watches every request time out one at a time.
//
// 25s interval matches docs/plans/2026-02-27-lightware-mx2-support-design.md
// (~line 63: "No dedicated ping command. Use periodic GET /.ProductName
// every 25 seconds.") — applied uniformly to all three protocols for one
// simple policy rather than a bespoke interval per adapter.
const KEEPALIVE_INTERVAL_MS = 25_000
// Require 2 consecutive misses before flipping state — tolerates a single
// dropped probe on flaky show-site Wi-Fi/switch hardware without flapping
// the connection indicator.
const KEEPALIVE_MISS_THRESHOLD = 2

let keepaliveTimer: NodeJS.Timeout | null = null
let missedBeats = 0

type SessionListener = (session: Readonly<RouterSession>) => void
const sessionListeners = new Set<SessionListener>()

/** Subscribe to session state transitions (used by ipc-handlers to push 'connection-status'/'error' events). Returns an unsubscribe function. */
export function onSessionChange(listener: SessionListener): () => void {
  sessionListeners.add(listener)
  return () => sessionListeners.delete(listener)
}

function notifySessionListeners(): void {
  const snapshot = { ...session }
  for (const listener of sessionListeners) listener(snapshot)
}

async function probeLiveness(ip: string, type: RouterType): Promise<boolean> {
  try {
    switch (type) {
      case 'kumo':
        return (await kumoProbeSystemName(ip)) !== null
      case 'videohub':
        return await videohubProbe(ip)
      case 'lightware':
        return await lightwareProbe(ip)
    }
  } catch {
    return false
  }
}

function stopKeepalive(): void {
  if (keepaliveTimer) {
    clearInterval(keepaliveTimer)
    keepaliveTimer = null
  }
  missedBeats = 0
}

function startKeepalive(): void {
  stopKeepalive()
  keepaliveTimer = setInterval(() => {
    void (async () => {
      if (!session.routerType || !session.ip) return
      const alive = await probeLiveness(session.ip, session.routerType)
      if (alive) {
        markSeen()
      } else {
        missedBeats++
        if (missedBeats >= KEEPALIVE_MISS_THRESHOLD) {
          markDead(`No response to liveness check after ${missedBeats} attempts`)
        }
      }
    })()
  }, KEEPALIVE_INTERVAL_MS)
  // Node timers hold the event loop open by default; a pending keepalive
  // must never block app quit.
  keepaliveTimer.unref?.()
}

/** Record fresh evidence the router is alive (successful op or keepalive probe). Auto-recovers from 'error' back to 'connected'. */
function markSeen(): void {
  session.lastSeenAt = Date.now()
  missedBeats = 0
  if (session.state === 'error') {
    session.state = 'connected'
    session.lastError = undefined
    notifySessionListeners()
  }
}

/** Flag the session as dead. Keeps the keepalive timer running so a router that comes back (e.g. after a reboot) is auto-detected via markSeen(). */
function markDead(reason: string): void {
  if (session.state !== 'connected') return
  session.state = 'error'
  session.lastError = reason
  notifySessionListeners()
}

function ensureConnected(): RouterSession {
  if (session.state !== 'connected' || !session.routerType || !session.ip) {
    if (session.state === 'error') {
      throw new Error(
        `Lost connection to ${session.routerType ?? 'router'} at ${session.ip}` +
        (session.lastError ? ` (${session.lastError})` : '') +
        '. Reconnect to continue.'
      )
    }
    throw new Error('Not connected to any router')
  }
  return session
}

export function getConnectionState() {
  return {
    ip: session.ip,
    routerType: session.routerType,
    inputCount: session.inputCount,
    outputCount: session.outputCount,
    state: session.state,
  }
}

export async function connect(
  ip: string,
  routerType?: RouterType,
  onProgress?: (done: number, total: number) => void
): Promise<ConnectResult> {
  stopKeepalive()

  const type = routerType || await detectRouterType(ip)
  if (!type) {
    session = emptySession()
    notifySessionListeners()
    return { success: false, routerType: 'kumo', deviceName: '', inputCount: 0, outputCount: 0, error: `No router detected at ${ip}` }
  }

  let result: ConnectResult
  switch (type) {
    case 'kumo':
      result = await kumoConnect(ip)
      break
    case 'videohub':
      result = await videohubConnect(ip)
      break
    case 'lightware':
      result = await lightwareConnect(ip)
      break
  }

  if (result.success) {
    session = {
      ip,
      routerType: type,
      inputCount: result.inputCount,
      outputCount: result.outputCount,
      state: 'connected',
      lastSeenAt: Date.now(),
      lastError: undefined,
    }
    startKeepalive()
  } else {
    session = emptySession()
  }
  notifySessionListeners()

  return result
}

export function disconnect(): void {
  stopKeepalive()
  session = emptySession()
  notifySessionListeners()
}

export async function download(
  onProgress?: (done: number, total: number) => void
): Promise<Label[]> {
  const s = ensureConnected()
  try {
    let labels: Label[]
    switch (s.routerType) {
      case 'kumo':
        labels = await kumoDownloadLabels(s.ip, s.inputCount, onProgress)
        break
      case 'videohub':
        labels = await videohubDownloadLabels(s.ip)
        break
      case 'lightware':
        labels = await lightwareDownloadLabels(s.ip)
        break
      default:
        labels = []
    }
    markSeen()
    return labels
  } catch (e) {
    markDead(String(e))
    throw e
  }
}

export async function upload(
  labels: Label[],
  onProgress?: (done: number, total: number) => void
): Promise<UploadResult> {
  const s = ensureConnected()
  try {
    let result: UploadResult
    switch (s.routerType) {
      case 'kumo':
        result = await kumoUploadLabels(s.ip, labels, onProgress)
        break
      case 'videohub':
        result = await videohubUploadLabels(s.ip, labels)
        break
      case 'lightware':
        result = await lightwareUploadLabels(s.ip, labels)
        break
      default:
        result = { successCount: 0, errorCount: 0, errors: [], results: [] }
    }
    // A batch that attempted at least one port write and got zero successes
    // is a strong liveness signal (every write already went through the
    // shared retry/backoff policy before failing) — flag the session dead
    // immediately instead of waiting for the next scheduled keepalive tick.
    if (result.results.length > 0 && result.successCount === 0 && result.errorCount > 0) {
      markDead(result.errors[0] || 'All port writes failed')
    } else {
      markSeen()
    }
    return result
  } catch (e) {
    markDead(String(e))
    throw e
  }
}

export async function getCrosspoints(): Promise<Crosspoint[]> {
  const s = ensureConnected()
  try {
    let result: Crosspoint[]
    switch (s.routerType) {
      case 'kumo':
        result = await kumoGetCrosspoints(s.ip, s.outputCount)
        break
      case 'videohub':
        result = await videohubGetRouting(s.ip)
        break
      case 'lightware':
        result = await lightwareGetRouting(s.ip)
        break
      default:
        result = []
    }
    markSeen()
    return result
  } catch (e) {
    markDead(String(e))
    throw e
  }
}

export async function setRoute(output: number, input: number): Promise<boolean> {
  const s = ensureConnected()
  try {
    let ok: boolean
    switch (s.routerType) {
      case 'kumo':
        // KUMO uses 1-based ports
        ok = await kumoSetRoute(s.ip, output + 1, input + 1)
        break
      case 'videohub':
        // Videohub uses 0-based
        ok = await videohubSetRoute(s.ip, output, input)
        break
      case 'lightware':
        // Lightware conversion handled inside lightwareSetRoute
        ok = await lightwareSetRoute(s.ip, output, input)
        break
      default:
        ok = false
    }
    // Deliberately not marking the session dead on ok === false: a rejected
    // route (e.g. a locked Videohub output) is a legitimate protocol-level
    // refusal, not necessarily a dead connection — only a thrown exception
    // (connection-level failure) counts as a liveness signal here.
    markSeen()
    return ok
  } catch (e) {
    markDead(String(e))
    throw e
  }
}

// Videohub-only: locks + take mode, previously parsed off the dump and
// discarded. See VideohubStatus in types.ts for the shape a future UI would
// consume (block/grey-out writes to outputs whose lock state isn't 'U').
export async function getVideohubStatus(): Promise<VideohubStatus | null> {
  if (session.state !== 'connected' || session.routerType !== 'videohub' || !session.ip) return null
  try {
    const status = await videohubGetStatus(session.ip)
    markSeen()
    return status
  } catch (e) {
    markDead(String(e))
    throw e
  }
}
