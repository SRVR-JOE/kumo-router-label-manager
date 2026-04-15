// Auto-detect router type by probing ports sequentially:
// 1. Lightware (TCP 6107) - fastest to respond if present
// 2. Videohub (TCP 9990)
// 3. KUMO (HTTP 80)

import { RouterType } from './types'
import { kumoTestConnection } from './kumo-rest'
import { probePort } from './net-utils'

const PROBE_TIMEOUT = 2500
const LIGHTWARE_PORT = 6107
const VIDEOHUB_PORT = 9990

export async function detectRouterType(ip: string): Promise<RouterType | null> {
  if (await probePort(ip, LIGHTWARE_PORT, PROBE_TIMEOUT)) return 'lightware'
  if (await probePort(ip, VIDEOHUB_PORT, PROBE_TIMEOUT)) return 'videohub'
  if (await kumoTestConnection(ip)) return 'kumo'
  return null
}
