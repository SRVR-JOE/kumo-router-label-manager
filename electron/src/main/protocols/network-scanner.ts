// IP range scanner — probes a /24 subnet for routers
// Checks ports 6107 (Lightware), 9990 (Videohub), 80 (KUMO) in parallel batches

import * as net from 'net'
import { RouterType } from './types'
import { kumoTestConnection } from './kumo-rest'

const SCAN_PROBE_TIMEOUT = 500
const BATCH_SIZE = 25

export interface DiscoveredRouter {
  ip: string
  routerType: RouterType
  deviceName: string
}

export interface ScanProgress {
  scanned: number
  total: number
  found: DiscoveredRouter[]
}

function probePort(ip: string, port: number, timeout = SCAN_PROBE_TIMEOUT): Promise<boolean> {
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
      sock.destroy()
      resolve(false)
    })
  })
}

async function detectAtIp(ip: string): Promise<{ routerType: RouterType; deviceName: string } | null> {
  // Probe all three ports in parallel for speed
  const [lightware, videohub, kumo] = await Promise.all([
    probePort(ip, 6107),
    probePort(ip, 9990),
    probePort(ip, 80).then(async (open) => {
      if (!open) return false
      // Port 80 is common — confirm it's actually a KUMO
      try {
        return await kumoTestConnection(ip)
      } catch {
        return false
      }
    }),
  ])

  if (lightware) return { routerType: 'lightware', deviceName: `Lightware @ ${ip}` }
  if (videohub) return { routerType: 'videohub', deviceName: `Videohub @ ${ip}` }
  if (kumo) return { routerType: 'kumo', deviceName: `KUMO @ ${ip}` }

  return null
}

/**
 * Scan a /24 subnet for routers.
 * @param baseIp - Subnet prefix, e.g. "192.168.100" (the .x part is scanned 1-254)
 * @param onProgress - Called after each batch with current progress
 * @returns Array of all discovered routers
 */
export async function scanSubnet(
  baseIp: string,
  onProgress?: (progress: ScanProgress) => void,
): Promise<DiscoveredRouter[]> {
  // Normalise: strip trailing dot or .x / .0
  const base = baseIp.replace(/\.\d+$/, '').replace(/\.$/, '')

  const found: DiscoveredRouter[] = []
  const total = 254
  let scanned = 0

  // Process in batches to avoid flooding the network
  for (let batchStart = 1; batchStart <= 254; batchStart += BATCH_SIZE) {
    const batchEnd = Math.min(batchStart + BATCH_SIZE - 1, 254)
    const batchPromises: Promise<void>[] = []

    for (let i = batchStart; i <= batchEnd; i++) {
      const ip = `${base}.${i}`
      batchPromises.push(
        detectAtIp(ip).then((result) => {
          if (result) {
            const router: DiscoveredRouter = { ip, ...result }
            found.push(router)
          }
        }),
      )
    }

    await Promise.all(batchPromises)
    scanned = Math.min(batchEnd, 254)

    if (onProgress) {
      onProgress({ scanned, total, found: [...found] })
    }
  }

  return found
}
