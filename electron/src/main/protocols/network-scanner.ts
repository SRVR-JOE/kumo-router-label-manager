// IP range scanner — probes a /24 subnet for routers
// Checks ports 6107 (Lightware), 9990 (Videohub), 80 (KUMO) in parallel.

import { RouterType } from './types'
import { kumoTestConnection } from './kumo-rest'
import { probePort } from './net-utils'

const SCAN_PROBE_TIMEOUT = 500
const LIGHTWARE_PORT = 6107
const VIDEOHUB_PORT = 9990
const KUMO_HTTP_PORT = 80

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

async function detectAtIp(ip: string): Promise<{ routerType: RouterType; deviceName: string } | null> {
  // Probe all three ports in parallel for speed
  const [lightware, videohub, kumo] = await Promise.all([
    probePort(ip, LIGHTWARE_PORT, SCAN_PROBE_TIMEOUT),
    probePort(ip, VIDEOHUB_PORT, SCAN_PROBE_TIMEOUT),
    probePort(ip, KUMO_HTTP_PORT, SCAN_PROBE_TIMEOUT).then(async (open) => {
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
const MAX_CONCURRENT_PROBES = 50

export async function scanSubnet(
  baseIp: string,
  onProgress?: (progress: ScanProgress) => void,
): Promise<DiscoveredRouter[]> {
  // Normalise: strip trailing dot or .x / .0
  const base = baseIp.replace(/\.\d+$/, '').replace(/\.$/, '')

  const found: DiscoveredRouter[] = []
  const total = 254
  let scanned = 0
  let nextHost = 1

  // Worker-pool pattern: N workers pull from a shared counter.
  // Reports progress after every probe completes rather than every batch.
  async function worker(): Promise<void> {
    while (nextHost <= total) {
      const host = nextHost++
      const ip = `${base}.${host}`
      const result = await detectAtIp(ip)
      if (result) {
        found.push({ ip, ...result })
      }
      scanned++
      if (onProgress) {
        onProgress({ scanned, total, found: [...found] })
      }
    }
  }

  const workerCount = Math.min(MAX_CONCURRENT_PROBES, total)
  await Promise.all(Array.from({ length: workerCount }, () => worker()))
  return found
}
