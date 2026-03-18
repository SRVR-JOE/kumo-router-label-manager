// AJA KUMO Telnet client (port 23)
// Fallback when REST API is not available

import * as net from 'net'
import { Label, KUMO_DEFAULT_COLOR } from './types'

const TELNET_PORT = 23
const CONNECT_TIMEOUT = 3000
const COMMAND_TIMEOUT = 2000
const COMMAND_DELAY = 100
const INITIAL_DELAY = 500

const LABEL_RESPONSE_RE = /"([^"]+)"/

function escapeLabel(label: string): string {
  return label.replace(/"/g, '\\"').replace(/[\r\n]/g, '')
}

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

class KumoTelnetClient {
  private socket: net.Socket | null = null
  private buffer = ''

  async connect(ip: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const sock = new net.Socket()
      const timer = setTimeout(() => {
        sock.destroy()
        reject(new Error(`Connection to ${ip}:${TELNET_PORT} timed out`))
      }, CONNECT_TIMEOUT)

      sock.connect(TELNET_PORT, ip, () => {
        clearTimeout(timer)
        this.socket = sock
        // Wait for initial prompt then clear it
        setTimeout(() => {
          this.buffer = ''
          resolve()
        }, INITIAL_DELAY)
      })

      sock.on('data', (data) => {
        this.buffer += data.toString('utf-8')
      })

      sock.on('error', (err) => {
        clearTimeout(timer)
        reject(new Error(`Connection to ${ip}:${TELNET_PORT} failed: ${err.message}`))
      })
    })
  }

  async sendCommand(command: string): Promise<string | null> {
    if (!this.socket) throw new Error('Not connected')

    this.buffer = ''
    this.socket.write(command + '\n')

    // Wait for response with timeout
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        const result = this.buffer.trim()
        resolve(result || null)
      }, COMMAND_TIMEOUT)

      const check = (): void => {
        if (this.buffer.includes('\n')) {
          clearTimeout(timer)
          resolve(this.buffer.trim())
        } else {
          setTimeout(check, 50)
        }
      }
      setTimeout(check, 50)
    })
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.destroy()
      this.socket = null
    }
  }
}

export async function kumoTelnetTestConnection(ip: string): Promise<boolean> {
  const client = new KumoTelnetClient()
  try {
    await client.connect(ip)
    client.disconnect()
    return true
  } catch {
    return false
  }
}

export async function kumoTelnetDownloadLabels(
  ip: string,
  portCount: number,
  onProgress?: (done: number, total: number) => void
): Promise<Label[]> {
  const client = new KumoTelnetClient()
  await client.connect(ip)

  const labels: Label[] = []
  const total = portCount * 2
  let done = 0

  try {
    // Download input labels
    for (let port = 1; port <= portCount; port++) {
      const response = await client.sendCommand(`LABEL INPUT ${port} ?`)
      let labelText = `Source ${port}`
      if (response) {
        const match = LABEL_RESPONSE_RE.exec(response)
        if (match) labelText = match[1]
      }
      labels.push({
        portNumber: port,
        portType: 'INPUT',
        currentLabel: labelText,
        newLabel: null,
        currentLabelLine2: '', // Telnet doesn't support line 2
        newLabelLine2: null,
        currentColor: KUMO_DEFAULT_COLOR, // Telnet doesn't support colors
        newColor: null,
        notes: '',
      })
      done++
      onProgress?.(done, total)
      await delay(COMMAND_DELAY)
    }

    // Download output labels
    for (let port = 1; port <= portCount; port++) {
      const response = await client.sendCommand(`LABEL OUTPUT ${port} ?`)
      let labelText = `Dest ${port}`
      if (response) {
        const match = LABEL_RESPONSE_RE.exec(response)
        if (match) labelText = match[1]
      }
      labels.push({
        portNumber: port,
        portType: 'OUTPUT',
        currentLabel: labelText,
        newLabel: null,
        currentLabelLine2: '',
        newLabelLine2: null,
        currentColor: KUMO_DEFAULT_COLOR,
        newColor: null,
        notes: '',
      })
      done++
      onProgress?.(done, total)
      await delay(COMMAND_DELAY)
    }
  } finally {
    client.disconnect()
  }

  return labels
}

export async function kumoTelnetUploadLabels(
  ip: string,
  labels: Label[],
  onProgress?: (done: number, total: number) => void
): Promise<{ successCount: number; errorCount: number; errors: string[] }> {
  const changes = labels.filter(l =>
    l.newLabel !== null && l.newLabel !== l.currentLabel
  )
  if (changes.length === 0) return { successCount: 0, errorCount: 0, errors: [] }

  const client = new KumoTelnetClient()
  await client.connect(ip)

  let successCount = 0
  let errorCount = 0
  const errors: string[] = []

  try {
    for (let i = 0; i < changes.length; i++) {
      const label = changes[i]
      const cmd = label.portType === 'INPUT'
        ? `LABEL INPUT ${label.portNumber} "${escapeLabel(label.newLabel!)}"`
        : `LABEL OUTPUT ${label.portNumber} "${escapeLabel(label.newLabel!)}"`

      const response = await client.sendCommand(cmd)
      if (response !== null) {
        successCount++
      } else {
        errorCount++
        errors.push(`Failed to set ${label.portType} ${label.portNumber}`)
      }
      onProgress?.(i + 1, changes.length)
      await delay(COMMAND_DELAY)
    }
  } finally {
    client.disconnect()
  }

  return { successCount, errorCount, errors }
}
