// Lightware MX2 LW3 TCP 6107 protocol
// Confirmed working against MX2-32x32-HDMI20-A-R at 192.168.100.51
//
// Key findings from live device:
//   - GETALL /MEDIA/XP/VIDEO returns DestinationConnectionStatus (NOT DestinationConnectionList)
//   - No .SourcePortCount / .DestinationPortCount — derive counts from label names
//   - CALL /MEDIA/XP/VIDEO:switch(I{n}:O{n}) works, returns "mO ...=OK"
//   - Labels: GET /MEDIA/NAMES/VIDEO.* → "pw ...I{n}={page};{name}"
//   - Product name: GET /.ProductName
//   - Serial: GET /.SerialNumber

import * as net from 'net'
import { Label, ConnectResult, UploadResult, KUMO_DEFAULT_COLOR } from './types'

const LIGHTWARE_PORT = 6107
const CONNECT_TIMEOUT = 5000
const COMMAND_TIMEOUT = 10000
const MAX_LABEL_LENGTH = 255

// ---------------------------------------------------------------------------
// Socket helpers
// ---------------------------------------------------------------------------

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

/**
 * Send an LW3 command wrapped in {NNNN#command\r\n} framing.
 * Collects all response lines between { } block markers.
 */
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
    }, COMMAND_TIMEOUT)

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

/** Check if a response line is an LW3 error */
function isErrorLine(line: string): boolean {
  return line.startsWith('pE') || line.startsWith('-E') || line.startsWith('nE')
}

/** Extract value from a property line like "pr /.ProductName=MX2-32x32" */
function extractValue(line: string): string | null {
  const eqIdx = line.indexOf('=')
  return eqIdx >= 0 ? line.slice(eqIdx + 1) : null
}

// ---------------------------------------------------------------------------
// Connect
// ---------------------------------------------------------------------------

export async function lightwareConnect(ip: string): Promise<ConnectResult> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    return { success: false, routerType: 'lightware', deviceName: '', inputCount: 0, outputCount: 0, error: String(e) }
  }

  const sendId = { value: 1 }

  try {
    // Product name
    let productName = 'Lightware MX2'
    const pnLines = await lw3SendCommand(sock, 'GET /.ProductName', sendId)
    console.log('[LW3] ProductName response lines:', pnLines.length, pnLines)
    for (const line of pnLines) {
      const val = extractValue(line)
      if (val) { productName = val; break }
    }

    // Get labels to derive port counts (SourcePortCount/DestinationPortCount don't exist on MX2)
    const labelLines = await lw3SendCommand(sock, 'GET /MEDIA/NAMES/VIDEO.*', sendId)
    console.log('[LW3] Label response lines:', labelLines.length)
    let inputCount = 0
    let outputCount = 0

    const inputRe = /\/MEDIA\/NAMES\/VIDEO\.I(\d+)=/
    const outputRe = /\/MEDIA\/NAMES\/VIDEO\.O(\d+)=/

    for (const line of labelLines) {
      let m = inputRe.exec(line)
      if (m) {
        const n = parseInt(m[1], 10)
        if (n > inputCount) inputCount = n
        continue
      }
      m = outputRe.exec(line)
      if (m) {
        const n = parseInt(m[1], 10)
        if (n > outputCount) outputCount = n
      }
    }

    console.log(`[LW3] Connect result: ${productName}, inputs=${inputCount}, outputs=${outputCount}`)
    return {
      success: true,
      routerType: 'lightware',
      deviceName: productName,
      inputCount,
      outputCount,
    }
  } catch (e) {
    return { success: false, routerType: 'lightware', deviceName: '', inputCount: 0, outputCount: 0, error: `Error querying device: ${e}` }
  } finally {
    sock.destroy()
  }
}

// ---------------------------------------------------------------------------
// Download labels
// ---------------------------------------------------------------------------

export async function lightwareDownloadLabels(ip: string): Promise<Label[]> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    throw new Error(`Cannot connect to Lightware at ${ip}: ${e}`)
  }

  const sendId = { value: 1 }

  try {
    // Get all labels — response: "pw /MEDIA/NAMES/VIDEO.I1=1;Input 1"
    const labelLines = await lw3SendCommand(sock, 'GET /MEDIA/NAMES/VIDEO.*', sendId)
    console.log('[LW3] Download label lines:', labelLines.length, labelLines.slice(0, 4))
    const inputLabels = new Map<number, string>()
    const outputLabels = new Map<number, string>()
    // Match with page;name format OR plain name (fallback)
    const inputRe = /\/MEDIA\/NAMES\/VIDEO\.I(\d+)=(?:\d+;)?(.*)/
    const outputRe = /\/MEDIA\/NAMES\/VIDEO\.O(\d+)=(?:\d+;)?(.*)/
    let inputCount = 0
    let outputCount = 0

    for (const line of labelLines) {
      let m = inputRe.exec(line)
      if (m) {
        const n = parseInt(m[1], 10)
        inputLabels.set(n, m[2])
        if (n > inputCount) inputCount = n
        continue
      }
      m = outputRe.exec(line)
      if (m) {
        const n = parseInt(m[1], 10)
        outputLabels.set(n, m[2])
        if (n > outputCount) outputCount = n
      }
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

// ---------------------------------------------------------------------------
// Get routing (crosspoints)
// ---------------------------------------------------------------------------

export async function lightwareGetRouting(ip: string): Promise<{ output: number; input: number }[]> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    throw new Error(`Cannot connect to Lightware at ${ip}: ${e}`)
  }

  const sendId = { value: 1 }

  try {
    // GETALL returns DestinationConnectionStatus: "I1;I22;I22;..."
    // This is a semicolon-separated list where index = output (0-based), value = input name
    const lines = await lw3SendCommand(sock, 'GETALL /MEDIA/XP/VIDEO', sendId)
    const crosspoints: { output: number; input: number }[] = []

    for (const line of lines) {
      if (line.includes('.DestinationConnectionStatus=')) {
        const val = extractValue(line)
        if (!val) break

        const entries = val.split(';').filter(s => s.length > 0)
        for (let o = 0; o < entries.length; o++) {
          const inputMatch = /^I(\d+)$/.exec(entries[o].trim())
          if (inputMatch) {
            crosspoints.push({
              output: o,
              input: parseInt(inputMatch[1], 10) - 1, // convert to 0-based
            })
          }
        }
        break
      }
    }

    return crosspoints
  } finally {
    sock.destroy()
  }
}

// ---------------------------------------------------------------------------
// Set route (single crosspoint)
// ---------------------------------------------------------------------------

export async function lightwareSetRoute(ip: string, output: number, input: number): Promise<boolean> {
  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch {
    return false
  }

  const sendId = { value: 1 }

  try {
    // CALL /MEDIA/XP/VIDEO:switch(I{input}:O{output}) — 1-based
    const command = `CALL /MEDIA/XP/VIDEO:switch(I${input + 1}:O${output + 1})`
    const lines = await lw3SendCommand(sock, command, sendId)

    // Success returns "mO /MEDIA/XP/VIDEO:switch=OK"
    for (const line of lines) {
      if (line.includes('mO') && line.includes('=OK')) {
        return true
      }
      if (isErrorLine(line)) {
        return false
      }
    }
    // If we got any response without error, assume success
    return lines.length > 0
  } finally {
    sock.destroy()
  }
}

// ---------------------------------------------------------------------------
// Upload labels
// ---------------------------------------------------------------------------

export async function lightwareUploadLabels(ip: string, labels: Label[]): Promise<UploadResult> {
  const changes = labels.filter(l => l.newLabel !== null && l.newLabel !== l.currentLabel)
  if (changes.length === 0) return { successCount: 0, errorCount: 0, errors: [] }

  let sock: net.Socket
  try {
    sock = await connectSocket(ip)
  } catch (e) {
    return { successCount: 0, errorCount: changes.length, errors: [`Connection failed: ${e}`] }
  }

  const sendId = { value: 1 }
  let successCount = 0
  let errorCount = 0
  const errors: string[] = []

  try {
    for (const label of changes) {
      const typeChar = label.portType === 'INPUT' ? 'I' : 'O'
      // Sanitize: strip semicolons from label text to avoid breaking the value format
      const labelText = label.newLabel!.replace(/;/g, '').slice(0, MAX_LABEL_LENGTH)
      // Format: SET /MEDIA/NAMES/VIDEO.I{n}={page};{name}
      // Page number doesn't affect the label — use 1
      const command = `SET /MEDIA/NAMES/VIDEO.${typeChar}${label.portNumber}=1;${labelText}`

      const responseLines = await lw3SendCommand(sock, command, sendId)

      let hasError = false
      for (const line of responseLines) {
        if (isErrorLine(line)) {
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
