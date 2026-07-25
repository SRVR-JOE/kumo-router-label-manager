// All ipcMain.handle() registrations

import { ipcMain, BrowserWindow, app } from 'electron'
import { isAbsolute, resolve as resolvePath, sep } from 'path'
import * as routerAgent from './protocols/router-agent'
import { detectRouterType } from './protocols/auto-detect'
import { scanSubnet } from './protocols/network-scanner'
import * as fileAgent from './file-io/file-agent'
import { getSettings, setSettings, addRecentFile, getRecentFiles } from './settings-store'
import { Label, PortData } from './protocols/types'
import { validateIpAddress, validatePortNumber } from './utils/validation'

function sendToRenderer(channel: string, ...args: unknown[]): void {
  const win = BrowserWindow.getAllWindows()[0]
  if (win) win.webContents.send(channel, ...args)
}

function isPrivateSubnetBase(base: string): boolean {
  // Accept "a.b.c" (3-octet prefix) where base IP is in RFC1918 range
  const parts = base.split('.')
  if (parts.length !== 3) return false
  const octets = parts.map(p => parseInt(p, 10))
  if (octets.some(n => isNaN(n) || n < 0 || n > 255)) return false
  if (parts.some((p, i) => String(octets[i]) !== p)) return false
  const [a, b] = octets
  if (a === 10) return true
  if (a === 172 && b >= 16 && b <= 31) return true
  if (a === 192 && b === 168) return true
  if (a === 169 && b === 254) return true // link-local
  return false
}

function isSafeUserPath(filePath: string): boolean {
  if (typeof filePath !== 'string' || !filePath) return false
  if (!isAbsolute(filePath)) return false
  const resolved = resolvePath(filePath)
  const allowedRoots = [
    app.getPath('documents'),
    app.getPath('desktop'),
    app.getPath('downloads'),
    app.getPath('userData'),
    app.getPath('home'),
    app.getPath('temp'),
  ].map(p => resolvePath(p))
  return allowedRoots.some(root => resolved === root || resolved.startsWith(root + sep))
}

export function registerIpcHandlers(): void {
  // Push proactive liveness transitions to the renderer. connect()/disconnect()
  // already emit 'connection-status' directly from their own handlers below;
  // this covers the case the old code couldn't: the session going dead *while
  // idle* (switch reboot, cable pull) via router-agent's keepalive, or a
  // download/upload/etc. discovering the router is gone.
  routerAgent.onSessionChange((s) => {
    if (s.state === 'error') {
      sendToRenderer('connection-status', 'error')
      sendToRenderer(
        'error',
        `Lost connection to ${s.routerType ?? 'router'} at ${s.ip}${s.lastError ? `: ${s.lastError}` : ''}. Reconnect to continue.`
      )
    } else if (s.state === 'connected') {
      sendToRenderer('connection-status', 'connected')
    }
  })

  // --- Router ---
  ipcMain.handle('router:connect', async (_event, ip: string, routerType?: string) => {
    if (!validateIpAddress(ip)) {
      sendToRenderer('connection-status', 'error')
      return { success: false, error: 'Invalid IP address', routerType: 'kumo', deviceName: '', inputCount: 0, outputCount: 0 }
    }
    const allowedTypes = ['kumo', 'videohub', 'lightware'] as const
    const typedRouter = (routerType && allowedTypes.includes(routerType as typeof allowedTypes[number]))
      ? (routerType as typeof allowedTypes[number])
      : undefined
    try {
      sendToRenderer('connection-status', 'connecting')
      const result = await routerAgent.connect(
        ip,
        typedRouter,
        (done, total) => sendToRenderer('progress', { done, total, phase: 'connect' })
      )
      sendToRenderer('connection-status', result.success ? 'connected' : 'disconnected')
      return result
    } catch (e) {
      sendToRenderer('connection-status', 'error')
      sendToRenderer('error', String(e))
      return { success: false, error: String(e), routerType: 'kumo', deviceName: '', inputCount: 0, outputCount: 0 }
    }
  })

  ipcMain.handle('router:disconnect', () => {
    routerAgent.disconnect()
    sendToRenderer('connection-status', 'disconnected')
  })

  ipcMain.handle('router:detect-type', async (_event, ip: string) => {
    if (!validateIpAddress(ip)) return null
    return detectRouterType(ip)
  })

  ipcMain.handle('router:scan-subnet', async (_event, baseIp: string) => {
    if (!isPrivateSubnetBase(baseIp)) {
      sendToRenderer('error', 'Subnet scan refused: base must be an RFC1918 private prefix (e.g. 192.168.1)')
      return []
    }
    try {
      const results = await scanSubnet(baseIp, (progress) => {
        sendToRenderer('scan-progress', progress)
      })
      return results
    } catch (e) {
      sendToRenderer('error', String(e))
      return []
    }
  })

  ipcMain.handle('router:download', async () => {
    try {
      const labels = await routerAgent.download(
        (done, total) => sendToRenderer('progress', { done, total, phase: 'download' })
      )
      return labels
    } catch (e) {
      sendToRenderer('error', String(e))
      return []
    }
  })

  ipcMain.handle('router:upload', async (_event, labels: Label[]) => {
    try {
      const result = await routerAgent.upload(
        labels,
        (done, total) => sendToRenderer('progress', { done, total, phase: 'upload' })
      )
      return result
    } catch (e) {
      sendToRenderer('error', String(e))
      return { successCount: 0, errorCount: 0, errors: [String(e)], results: [] }
    }
  })

  ipcMain.handle('router:get-videohub-status', async () => {
    try {
      return await routerAgent.getVideohubStatus()
    } catch (e) {
      sendToRenderer('error', String(e))
      return null
    }
  })

  ipcMain.handle('router:get-crosspoints', async () => {
    try {
      return await routerAgent.getCrosspoints()
    } catch (e) {
      sendToRenderer('error', String(e))
      return []
    }
  })

  ipcMain.handle('router:set-route', async (_event, output: number, input: number) => {
    if (!validatePortNumber(output) || !validatePortNumber(input)) return false
    try {
      return await routerAgent.setRoute(output, input)
    } catch (e) {
      sendToRenderer('error', String(e))
      return false
    }
  })

  // --- File ---
  ipcMain.handle('file:open', async () => {
    try {
      const data = await fileAgent.openFile()
      if (data?.filePath) addRecentFile(data.filePath)
      return data
    } catch (e) {
      sendToRenderer('error', String(e))
      return null
    }
  })

  ipcMain.handle('file:save', async (_event, path: string, data: { ports: PortData[] }) => {
    if (!isSafeUserPath(path)) {
      sendToRenderer('error', 'Save refused: path is outside allowed user directories')
      return
    }
    try {
      await fileAgent.saveFile(path, data)
      addRecentFile(path)
    } catch (e) {
      sendToRenderer('error', String(e))
    }
  })

  ipcMain.handle('file:save-as', async (_event, data: { ports: PortData[] }) => {
    try {
      const path = await fileAgent.saveFileAs(data)
      if (path) addRecentFile(path)
      return path
    } catch (e) {
      sendToRenderer('error', String(e))
      return null
    }
  })

  ipcMain.handle('file:create-template', async (_event, _path: string, portCount: number) => {
    try {
      return await fileAgent.createTemplate(portCount)
    } catch (e) {
      sendToRenderer('error', String(e))
      return null
    }
  })

  ipcMain.handle('file:get-recent', () => {
    return getRecentFiles()
  })

  ipcMain.handle('file:get-default-templates', () => {
    return fileAgent.getDefaultTemplates()
  })

  ipcMain.handle('file:open-default-template', async (_event, name: string) => {
    if (typeof name !== 'string' || !/^[A-Za-z0-9 _.\-]+$/.test(name)) {
      sendToRenderer('error', 'Template name contains disallowed characters')
      return null
    }
    try {
      return await fileAgent.openDefaultTemplate(name)
    } catch (e) {
      sendToRenderer('error', String(e))
      return null
    }
  })

  // --- Settings ---
  ipcMain.handle('settings:get', () => {
    return getSettings()
  })

  ipcMain.handle('settings:set', (_event, partial: Record<string, unknown>) => {
    setSettings(partial)
  })
}
