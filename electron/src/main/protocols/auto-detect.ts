// Auto-detect router type by probing ports sequentially:
// 1. Lightware (TCP 6107) - fastest to respond if present
// 2. Videohub (TCP 9990)
// 3. KUMO (HTTP 80)

import * as net from 'net'
import { RouterType } from './types'
import { kumoTestConnection } from './kumo-rest'

const PROBE_TIMEOUT = 2500

function probePort(ip: string, port: number, timeout = PROBE_TIMEOUT): Promise<boolean> {
  return new Promise((resolve) => {
    const sock = new net.Socket()
    const timer = setTimeout(() => {
      sock.destroy()
      resolve(false)
    }, timeout)

    sock.connect(port, ip, () => {
      clearTimeout(timer)
      sock.destroy()
      resolve(true)
    })

    sock.on('error', () => {
      clearTimeout(timer)
      resolve(false)
    })
  })
}

export async function detectRouterType(ip: string): Promise<RouterType | null> {
  // Probe Lightware (6107)
  if (await probePort(ip, 6107)) return 'lightware'

  // Probe Videohub (9990)
  if (await probePort(ip, 9990)) return 'videohub'

  // Probe KUMO (HTTP 80 REST API)
  if (await kumoTestConnection(ip)) return 'kumo'

  return null
}
