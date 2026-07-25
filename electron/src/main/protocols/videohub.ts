// Blackmagic Videohub TCP 9990 protocol
// Block-based text protocol with 300ms silence detection

import * as net from 'net'
import { Label, ConnectResult, UploadResult, PortUploadResult, VideohubStatus, KUMO_DEFAULT_COLOR } from './types'
import { withRetry } from './retry'
import { probePort } from './net-utils'
import { sanitizeLabel } from '../utils/validation'

const VIDEOHUB_PORT = 9990
const CONNECT_TIMEOUT = 2000
const MAX_LABEL_LENGTH = 255

interface VideohubInfo {
  modelName: string
  friendlyName: string
  protocolVersion: string
  videoInputs: number
  videoOutputs: number
  inputLabels: string[]
  outputLabels: string[]
  locks: Map<number, string>
  routing: Map<number, number>
  takeMode: boolean
}

function recvUntilSilence(sock: net.Socket, timeout = 5000): Promise<string> {
  return new Promise((resolve) => {
    let data = ''
    let silenceTimer: NodeJS.Timeout | null = null

    const finish = (): void => {
      sock.removeListener('data', onData)
      resolve(data)
    }

    const resetSilence = (): void => {
      if (silenceTimer) clearTimeout(silenceTimer)
      silenceTimer = setTimeout(finish, 300) // 300ms silence = dump complete
    }

    const globalTimer = setTimeout(() => {
      if (silenceTimer) clearTimeout(silenceTimer)
      finish()
    }, timeout)

    const onData = (chunk: Buffer): void => {
      data += chunk.toString('utf-8')
      resetSilence()
    }

    sock.on('data', onData)
    sock.once('end', () => {
      clearTimeout(globalTimer)
      if (silenceTimer) clearTimeout(silenceTimer)
      finish()
    })

    // Start the silence timer in case data comes immediately
    resetSilence()
  })
}

function parseVideohubDump(raw: string): VideohubInfo {
  const info: VideohubInfo = {
    modelName: 'Blackmagic Videohub',
    friendlyName: '',
    protocolVersion: 'Unknown',
    videoInputs: 0,
    videoOutputs: 0,
    inputLabels: [],
    outputLabels: [],
    locks: new Map(),
    routing: new Map(),
    takeMode: false,
  }

  // Parse blocks
  const blocks = new Map<string, string[]>()
  let currentBlock: string | null = null
  let currentLines: string[] = []

  for (const line of raw.split('\n')) {
    const stripped = line.trimEnd()
    if (stripped.endsWith(':') && !stripped.startsWith(' ') && !/^\d/.test(stripped)) {
      if (currentBlock !== null) blocks.set(currentBlock, currentLines)
      currentBlock = stripped.slice(0, -1)
      currentLines = []
    } else if (stripped === '') {
      if (currentBlock !== null) {
        blocks.set(currentBlock, currentLines)
        currentBlock = null
        currentLines = []
      }
    } else {
      if (currentBlock !== null) currentLines.push(stripped)
    }
  }
  if (currentBlock !== null) blocks.set(currentBlock, currentLines)

  // PROTOCOL PREAMBLE
  for (const entry of blocks.get('PROTOCOL PREAMBLE') || []) {
    if (entry.startsWith('Version:')) info.protocolVersion = entry.split(':')[1].trim()
  }

  // VIDEOHUB DEVICE
  for (const entry of blocks.get('VIDEOHUB DEVICE') || []) {
    if (entry.startsWith('Model name:')) info.modelName = entry.split(':').slice(1).join(':').trim()
    else if (entry.startsWith('Friendly name:')) info.friendlyName = entry.split(':').slice(1).join(':').trim()
    else if (entry.startsWith('Video inputs:')) info.videoInputs = parseInt(entry.split(':')[1].trim(), 10) || 0
    else if (entry.startsWith('Video outputs:')) info.videoOutputs = parseInt(entry.split(':')[1].trim(), 10) || 0
  }

  // Initialize default labels
  info.inputLabels = Array.from({ length: info.videoInputs }, (_, i) => `Input ${i + 1}`)
  info.outputLabels = Array.from({ length: info.videoOutputs }, (_, i) => `Output ${i + 1}`)

  // INPUT LABELS
  for (const entry of blocks.get('INPUT LABELS') || []) {
    const spaceIdx = entry.indexOf(' ')
    if (spaceIdx === -1) continue
    const idx = parseInt(entry.slice(0, spaceIdx), 10)
    const label = entry.slice(spaceIdx + 1)
    if (!isNaN(idx)) {
      while (info.inputLabels.length <= idx) info.inputLabels.push(`Input ${info.inputLabels.length + 1}`)
      info.inputLabels[idx] = label
    }
  }

  // OUTPUT LABELS
  for (const entry of blocks.get('OUTPUT LABELS') || []) {
    const spaceIdx = entry.indexOf(' ')
    if (spaceIdx === -1) continue
    const idx = parseInt(entry.slice(0, spaceIdx), 10)
    const label = entry.slice(spaceIdx + 1)
    if (!isNaN(idx)) {
      while (info.outputLabels.length <= idx) info.outputLabels.push(`Output ${info.outputLabels.length + 1}`)
      info.outputLabels[idx] = label
    }
  }

  // VIDEO OUTPUT LOCKS
  for (const entry of blocks.get('VIDEO OUTPUT LOCKS') || []) {
    const parts = entry.split(' ')
    if (parts.length === 2) {
      const idx = parseInt(parts[0], 10)
      if (!isNaN(idx)) info.locks.set(idx, parts[1].trim())
    }
  }

  // VIDEO OUTPUT ROUTING
  for (const entry of blocks.get('VIDEO OUTPUT ROUTING') || []) {
    const parts = entry.split(' ')
    if (parts.length === 2) {
      const outIdx = parseInt(parts[0], 10)
      const inIdx = parseInt(parts[1].trim(), 10)
      if (!isNaN(outIdx) && !isNaN(inIdx)) info.routing.set(outIdx, inIdx)
    }
  }

  // CONFIGURATION
  for (const entry of blocks.get('CONFIGURATION') || []) {
    if (entry.startsWith('Take Mode:')) {
      info.takeMode = entry.split(':')[1].trim().toLowerCase() === 'true'
    }
  }

  return info
}

function connectOnce(ip: string): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    const sock = new net.Socket()
    const timer = setTimeout(() => {
      sock.destroy()
      reject(new Error(`Connection to ${ip}:${VIDEOHUB_PORT} timed out`))
    }, CONNECT_TIMEOUT)

    sock.connect(VIDEOHUB_PORT, ip, () => {
      clearTimeout(timer)
      resolve(sock)
    })

    sock.on('error', (err) => {
      clearTimeout(timer)
      reject(new Error(`Cannot connect to ${ip}:${VIDEOHUB_PORT} — ${err.message}`))
    })
  })
}

// TCP connect is idempotent (no device-visible side effect), so it's safe to
// retry with the shared backoff policy — this is what actually fixes
// "flaky show-site network drops one packet and the whole operation fails".
function connectSocket(ip: string): Promise<net.Socket> {
  return withRetry(() => connectOnce(ip))
}

// Lightweight liveness probe used by router-agent's session keepalive.
// Reuses the plain TCP probe (no data exchange, no dump parsing) so a
// liveness check never blocks on/consumes an actual protocol round-trip.
export async function videohubProbe(ip: string): Promise<boolean> {
  return probePort(ip, VIDEOHUB_PORT, CONNECT_TIMEOUT)
}

function sendAndWaitAck(sock: net.Socket, payload: string, timeout = 5000): Promise<string> {
  return new Promise((resolve) => {
    let buf = ''
    const timer = setTimeout(() => {
      sock.removeListener('data', onData)
      resolve(buf)
    }, timeout)

    const onData = (chunk: Buffer): void => {
      buf += chunk.toString('utf-8')
      if (buf.includes('\n\n')) {
        clearTimeout(timer)
        sock.removeListener('data', onData)
        resolve(buf)
      }
    }

    sock.on('data', onData)
    sock.write(payload)
  })
}

export async function videohubConnect(ip: string): Promise<ConnectResult> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    return { success: false, routerType: 'videohub', deviceName: '', inputCount: 0, outputCount: 0, error: String(e) }
  }

  try {
    const raw = await recvUntilSilence(sock)
    if (!raw.trim()) {
      return { success: false, routerType: 'videohub', deviceName: '', inputCount: 0, outputCount: 0, error: 'No data received' }
    }
    const info = parseVideohubDump(raw)
    return {
      success: true,
      routerType: 'videohub',
      deviceName: info.friendlyName || info.modelName,
      inputCount: info.videoInputs,
      outputCount: info.videoOutputs,
    }
  } finally {
    sock.destroy()
  }
}

export async function videohubDownloadLabels(ip: string): Promise<Label[]> {
  const sock = await connectSocket(ip)
  try {
    const raw = await recvUntilSilence(sock)
    const info = parseVideohubDump(raw)
    const labels: Label[] = []

    for (let i = 0; i < info.inputLabels.length; i++) {
      labels.push({
        portNumber: i + 1,
        portType: 'INPUT',
        currentLabel: info.inputLabels[i],
        newLabel: null,
        currentLabelLine2: '',
        newLabelLine2: null,
        currentColor: KUMO_DEFAULT_COLOR,
        newColor: null,
        notes: '',
      })
    }
    for (let i = 0; i < info.outputLabels.length; i++) {
      labels.push({
        portNumber: i + 1,
        portType: 'OUTPUT',
        currentLabel: info.outputLabels[i],
        newLabel: null,
        currentLabelLine2: '',
        newLabelLine2: null,
        currentColor: KUMO_DEFAULT_COLOR,
        newColor: null,
        notes: '',
      })
    }

    return labels
  } finally {
    sock.destroy()
  }
}

export async function videohubUploadLabels(ip: string, labels: Label[]): Promise<UploadResult> {
  const changes = labels.filter(l => l.newLabel !== null && l.newLabel !== l.currentLabel)
  if (changes.length === 0) return { successCount: 0, errorCount: 0, errors: [], results: [] }

  const inputChanges = changes.filter(l => l.portType === 'INPUT')
  const outputChanges = changes.filter(l => l.portType === 'OUTPUT')

  let successCount = 0
  let errorCount = 0
  const errors: string[] = []
  const results: PortUploadResult[] = []

  // Videohub ACKs/NAKs an entire "LABELS:" block at once — there is no
  // per-line acknowledgement in this protocol, so the finest-grained truth
  // we can report is "every port in this block landed" or "none of them did".
  // Splitting into one SET per port to get finer granularity would change
  // request timing/behaviour against real hardware in a way we can't verify
  // here, so we keep the existing batched writes and attribute the shared
  // block outcome to each port in it.
  function recordBlock(blockLabel: string, portsInBlock: Label[], ack: string): void {
    if (ack.toUpperCase().includes('ACK')) {
      successCount += portsInBlock.length
      for (const lbl of portsInBlock) {
        results.push({ portNumber: lbl.portNumber, portType: lbl.portType, ok: true })
      }
    } else {
      const reason = ack.toUpperCase().includes('NAK') ? 'device returned NAK' : 'no ACK received'
      errorCount += portsInBlock.length
      errors.push(`${blockLabel}: ${reason}`)
      for (const lbl of portsInBlock) {
        results.push({ portNumber: lbl.portNumber, portType: lbl.portType, ok: false, error: `${blockLabel} block: ${reason}` })
      }
    }
  }

  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    // Could not even establish the connection — every pending change is
    // unconfirmed, but we still report one result entry per port so callers
    // can rely on results.length === changes.length whenever changes exist.
    const reason = `Connection failed: ${e}`
    for (const lbl of changes) {
      results.push({ portNumber: lbl.portNumber, portType: lbl.portType, ok: false, error: reason })
    }
    return { successCount: 0, errorCount: changes.length, errors: [reason], results }
  }

  try {
    // Drain initial dump
    await recvUntilSilence(sock, 2000)

    // Send input labels block
    if (inputChanges.length > 0) {
      const lines = ['INPUT LABELS:']
      for (const lbl of inputChanges) {
        // Strip CR/LF before framing: this is a line-oriented protocol, so an
        // embedded newline injects an extra raw line into the block and shifts
        // port attribution for every line after it.
        lines.push(`${lbl.portNumber - 1} ${sanitizeLabel(lbl.newLabel!, MAX_LABEL_LENGTH)}`)
      }
      lines.push('', '')
      const payload = lines.join('\n')
      const ack = await sendAndWaitAck(sock, payload)
      recordBlock('INPUT LABELS', inputChanges, ack)
    }

    // Send output labels block
    if (outputChanges.length > 0) {
      const lines = ['OUTPUT LABELS:']
      for (const lbl of outputChanges) {
        // See INPUT LABELS above — CR/LF must not reach the wire block.
        lines.push(`${lbl.portNumber - 1} ${sanitizeLabel(lbl.newLabel!, MAX_LABEL_LENGTH)}`)
      }
      lines.push('', '')
      const payload = lines.join('\n')
      const ack = await sendAndWaitAck(sock, payload)
      recordBlock('OUTPUT LABELS', outputChanges, ack)
    }
  } finally {
    sock.destroy()
  }

  return { successCount, errorCount, errors, results }
}

// Locks + take mode are parsed off the device dump but were previously
// discarded entirely. Surfaced here (main-process only, no UI) so a future
// grid can grey out / block writes to locked outputs. See VideohubStatus in
// types.ts for the shape a UI would consume.
export async function videohubGetStatus(ip: string): Promise<VideohubStatus> {
  const sock = await connectSocket(ip)
  try {
    const raw = await recvUntilSilence(sock)
    const info = parseVideohubDump(raw)
    const locks = Array.from(info.locks, ([output, state]) => ({ output, state }))
    return { locks, takeMode: info.takeMode }
  } finally {
    sock.destroy()
  }
}

export async function videohubGetRouting(ip: string): Promise<{ output: number; input: number }[]> {
  const sock = await connectSocket(ip)
  try {
    const raw = await recvUntilSilence(sock)
    const info = parseVideohubDump(raw)
    const crosspoints: { output: number; input: number }[] = []
    for (const [out, inp] of info.routing) {
      crosspoints.push({ output: out, input: inp })
    }
    return crosspoints
  } finally {
    sock.destroy()
  }
}

export async function videohubSetRoute(ip: string, output: number, input: number): Promise<boolean> {
  const sock = await connectSocket(ip)
  try {
    await recvUntilSilence(sock, 2000)
    const payload = `VIDEO OUTPUT ROUTING:\n${output} ${input}\n\n`
    const ack = await sendAndWaitAck(sock, payload)
    return ack.toUpperCase().includes('ACK')
  } finally {
    sock.destroy()
  }
}
