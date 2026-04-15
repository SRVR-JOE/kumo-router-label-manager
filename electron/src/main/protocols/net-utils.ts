// Shared net helpers used by auto-detect and network-scanner.

import * as net from 'net'

/**
 * TCP connect probe with timeout. Returns true if the port accepts a connection.
 * Resolves (never rejects) so callers can treat it as a simple boolean.
 */
export function probePort(ip: string, port: number, timeout: number): Promise<boolean> {
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
