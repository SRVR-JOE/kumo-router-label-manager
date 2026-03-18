// All ipcMain.handle() registrations

import { ipcMain, BrowserWindow } from 'electron'
import * as routerAgent from './protocols/router-agent'
import { detectRouterType } from './protocols/auto-detect'
import * as fileAgent from './file-io/file-agent'
import { getSettings, setSettings, addRecentFile, getRecentFiles } from './settings-store'
import { Label, PortData } from './protocols/types'

function sendToRenderer(channel: string, ...args: unknown[]): void {
  const win = BrowserWindow.getAllWindows()[0]
  if (win) win.webContents.send(channel, ...args)
}

export function registerIpcHandlers(): void {
  // --- Router ---
  ipcMain.handle('router:connect', async (_event, ip: string, routerType?: string) => {
    try {
      sendToRenderer('connection-status', 'connecting')
      const result = await routerAgent.connect(
        ip,
        routerType as 'kumo' | 'videohub' | 'lightware' | undefined,
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
    return detectRouterType(ip)
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
      return { successCount: 0, errorCount: 0, errors: [String(e)] }
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

  // --- Settings ---
  ipcMain.handle('settings:get', () => {
    return getSettings()
  })

  ipcMain.handle('settings:set', (_event, partial: Record<string, unknown>) => {
    setSettings(partial)
  })
}
