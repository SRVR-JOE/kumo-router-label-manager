// Lightware MX2 LW3 TCP 6107 protocol
// Framed requests: {NNNN#command\r\n} -> {NNNN ... }

import * as net from 'net'
import { Label, ConnectResult, UploadResult, KUMO_DEFAULT_COLOR } from './types'

const LIGHTWARE_PORT = 6107
const CONNECT_TIMEOUT = 2000
const MAX_LABEL_LENGTH = 255

function connectSocket(ip: string, port = LIGHTWARE_PORT): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    const sock = new net.Socket()
    const timer = setTimeout(() => {
      sock.destroy()
      reject(new Error(`Connection to ${ip}:${port} timed out`))
    }, CONNECT_TIMEOUT)

    sock.connect(port, ip, () => {
      clearTimeout(timer)
      resolve(sock)
    })

    sock.on('error', (err) => {
      clearTimeout(timer)
      reject(new Error(`Cannot connect to ${ip}:${port} — ${err.message}`))
    })
  })
}

function lw3SendCommand(
  sock: net.Socket,
  command: string,
  sendId: { value: number }
): Promise<string[]> {
  return new Promise((resolve) => {
    const reqId = sendId.value++
    const idStr = String(reqId).padStart(4, '0')
    const framed = `${idStr}#${command}\r\n`
    const expectedOpen = `{${idStr}`
    const expectedClose = '}'

    const lines: string[] = []
    let inBlock = false
    let buf = ''

    const deadline = setTimeout(() => {
      sock.removeListener('data', onData)
      resolve(lines)
    }, 5000)

    const onData = (chunk: Buffer): void => {
      buf += chunk.toString('ascii')

      while (buf.includes('\n')) {
        const nlIdx = buf.indexOf('\n')
        const rawLine = buf.slice(0, nlIdx).replace(/\r$/, '')
        buf = buf.slice(nlIdx + 1)

        if (!inBlock) {
          if (rawLine.startsWith(expectedOpen)) {
            inBlock = true
          }
          continue
        }

        if (rawLine.trim() === expectedClose) {
          clearTimeout(deadline)
          sock.removeListener('data', onData)
          resolve(lines)
          return
        }

        lines.push(rawLine)
      }
    }

    sock.on('data', onData)

    try {
      sock.write(framed, 'ascii')
    } catch {
      clearTimeout(deadline)
      sock.removeListener('data', onData)
      resolve([])
    }
  })
}

interface LightwareInfo {
  productName: string
  inputCount: number
  outputCount: number
  inputLabels: Map<number, string>
  outputLabels: Map<number, string>
}

export async function lightwareConnect(ip: string): Promise<ConnectResult> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    return { success: false, routerType: 'lightware', deviceName: '', inputCount: 0, outputCount: 0, error: String(e) }
  }

  const sendId = { value: 1 }
  const info: LightwareInfo = {
    productName: 'Lightware MX2',
    inputCount: 0,
    outputCount: 0,
    inputLabels: new Map(),
    outputLabels: new Map(),
  }

  try {
    // Product name
    const pnLines = await lw3SendCommand(sock, 'GET /.ProductName', sendId)
    for (const line of pnLines) {
      if (line.includes('=')) {
        info.productName = line.split('=')[1].trim()
        break
      }
    }

    // Source port count
    const srcLines = await lw3SendCommand(sock, 'GET /MEDIA/XP/VIDEO.SourcePortCount', sendId)
    for (const line of srcLines) {
      if (line.includes('=')) {
        info.inputCount = parseInt(line.split('=')[1].trim(), 10) || 0
        break
      }
    }

    // Destination port count
    const dstLines = await lw3SendCommand(sock, 'GET /MEDIA/XP/VIDEO.DestinationPortCount', sendId)
    for (const line of dstLines) {
      if (line.includes('=')) {
        info.outputCount = parseInt(line.split('=')[1].trim(), 10) || 0
        break
      }
    }

    // Labels (wildcard GET)
    const labelLines = await lw3SendCommand(sock, 'GET /MEDIA/NAMES/VIDEO.*', sendId)
    const inputRe = /\/MEDIA\/NAMES\/VIDEO\.I(\d+)=\d+;(.*)/
    const outputRe = /\/MEDIA\/NAMES\/VIDEO\.O(\d+)=\d+;(.*)/

    for (const line of labelLines) {
      let m = inputRe.exec(line)
      if (m) {
        info.inputLabels.set(parseInt(m[1], 10), m[2])
        continue
      }
      m = outputRe.exec(line)
      if (m) {
        info.outputLabels.set(parseInt(m[1], 10), m[2])
      }
    }

    // Fill defaults
    for (let i = 1; i <= info.inputCount; i++) {
      if (!info.inputLabels.has(i)) info.inputLabels.set(i, `Input ${i}`)
    }
    for (let i = 1; i <= info.outputCount; i++) {
      if (!info.outputLabels.has(i)) info.outputLabels.set(i, `Output ${i}`)
    }

    return {
      success: true,
      routerType: 'lightware',
      deviceName: info.productName,
      inputCount: info.inputCount,
      outputCount: info.outputCount,
    }
  } catch (e) {
    return { success: false, routerType: 'lightware', deviceName: '', inputCount: 0, outputCount: 0, error: `Error querying device: ${e}` }
  } finally {
    sock.destroy()
  }
}

export async function lightwareDownloadLabels(ip: string): Promise<Label[]> {
  const sock = await connectSocket(ip)
  const sendId = { value: 1 }

  try {
    // Get port counts
    let inputCount = 0
    let outputCount = 0

    const srcLines = await lw3SendCommand(sock, 'GET /MEDIA/XP/VIDEO.SourcePortCount', sendId)
    for (const line of srcLines) {
      if (line.includes('=')) { inputCount = parseInt(line.split('=')[1].trim(), 10) || 0; break }
    }
    const dstLines = await lw3SendCommand(sock, 'GET /MEDIA/XP/VIDEO.DestinationPortCount', sendId)
    for (const line of dstLines) {
      if (line.includes('=')) { outputCount = parseInt(line.split('=')[1].trim(), 10) || 0; break }
    }

    // Get all labels
    const labelLines = await lw3SendCommand(sock, 'GET /MEDIA/NAMES/VIDEO.*', sendId)
    const inputLabels = new Map<number, string>()
    const outputLabels = new Map<number, string>()
    const inputRe = /\/MEDIA\/NAMES\/VIDEO\.I(\d+)=\d+;(.*)/
    const outputRe = /\/MEDIA\/NAMES\/VIDEO\.O(\d+)=\d+;(.*)/

    for (const line of labelLines) {
      let m = inputRe.exec(line)
      if (m) { inputLabels.set(parseInt(m[1], 10), m[2]); continue }
      m = outputRe.exec(line)
      if (m) { outputLabels.set(parseInt(m[1], 10), m[2]) }
    }

    const labels: Label[] = []
    for (let i = 1; i <= inputCount; i++) {
      labels.push({
        portNumber: i,
        portType: 'INPUT',
        currentLabel: inputLabels.get(i) || `Input ${i}`,
        newLabel: null,
        currentLabelLine2: '',
        newLabelLine2: null,
        currentColor: KUMO_DEFAULT_COLOR,
        newColor: null,
        notes: '',
      })
    }
    for (let i = 1; i <= outputCount; i++) {
      labels.push({
        portNumber: i,
        portType: 'OUTPUT',
        currentLabel: outputLabels.get(i) || `Output ${i}`,
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

export async function lightwareUploadLabels(ip: string, labels: Label[]): Promise<UploadResult> {
  const changes = labels.filter(l => l.newLabel !== null && l.newLabel !== l.currentLabel)
  if (changes.length === 0) return { successCount: 0, errorCount: 0, errors: [] }

  let successCount = 0
  let errorCount = 0
  const errors: string[] = []

  // Open one connection for all changes
  const sock = await connectSocket(ip)
  const sendId = { value: 1 }

  try {
    for (const label of changes) {
      const typeChar = label.portType === 'INPUT' ? 'I' : 'O'
      const labelText = label.newLabel!.slice(0, MAX_LABEL_LENGTH)
      const path = `/MEDIA/NAMES/VIDEO.${typeChar}${label.portNumber}=${label.portNumber};${labelText}`
      const command = `SET ${path}`

      const responseLines = await lw3SendCommand(sock, command, sendId)

      let hasError = false
      for (const line of responseLines) {
        if (line.startsWith('pE') || line.startsWith('nE') || line.startsWith('-E')) {
          hasError = true
          errors.push(`${label.portType} ${label.portNumber}: ${line}`)
          break
        }
      }

      if (hasError || responseLines.length === 0) {
        errorCount++
        if (responseLines.length === 0) {
          errors.push(`${label.portType} ${label.portNumber}: no response`)
        }
      } else {
        successCount++
      }
    }
  } finally {
    sock.destroy()
  }

  return { successCount, errorCount, errors }
}
