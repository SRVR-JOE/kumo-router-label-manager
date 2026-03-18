// Unified router facade — dispatches to the correct protocol

import { RouterType, Label, ConnectResult, UploadResult, Crosspoint } from './types'
import { detectRouterType } from './auto-detect'
import { kumoConnect, kumoDownloadLabels, kumoUploadLabels, kumoGetCrosspoints, kumoSetRoute } from './kumo-rest'
import { videohubConnect, videohubDownloadLabels, videohubUploadLabels, videohubGetRouting, videohubSetRoute } from './videohub'
import { lightwareConnect, lightwareDownloadLabels, lightwareUploadLabels } from './lightware'

let currentIp = ''
let currentType: RouterType | null = null
let currentInputCount = 0
let currentOutputCount = 0

export function getConnectionState() {
  return { ip: currentIp, routerType: currentType, inputCount: currentInputCount, outputCount: currentOutputCount }
}

export async function connect(
  ip: string,
  routerType?: RouterType,
  onProgress?: (done: number, total: number) => void
): Promise<ConnectResult> {
  const type = routerType || await detectRouterType(ip)
  if (!type) {
    return { success: false, routerType: 'kumo', deviceName: '', inputCount: 0, outputCount: 0, error: `No router detected at ${ip}` }
  }

  let result: ConnectResult
  switch (type) {
    case 'kumo':
      result = await kumoConnect(ip)
      break
    case 'videohub':
      result = await videohubConnect(ip)
      break
    case 'lightware':
      result = await lightwareConnect(ip)
      break
  }

  if (result.success) {
    currentIp = ip
    currentType = type
    currentInputCount = result.inputCount
    currentOutputCount = result.outputCount
  }

  return result
}

export function disconnect(): void {
  currentIp = ''
  currentType = null
  currentInputCount = 0
  currentOutputCount = 0
}

export async function download(
  onProgress?: (done: number, total: number) => void
): Promise<Label[]> {
  if (!currentType || !currentIp) throw new Error('Not connected to any router')

  switch (currentType) {
    case 'kumo':
      return kumoDownloadLabels(currentIp, currentInputCount, onProgress)
    case 'videohub':
      return videohubDownloadLabels(currentIp)
    case 'lightware':
      return lightwareDownloadLabels(currentIp)
  }
}

export async function upload(
  labels: Label[],
  onProgress?: (done: number, total: number) => void
): Promise<UploadResult> {
  if (!currentType || !currentIp) throw new Error('Not connected to any router')

  switch (currentType) {
    case 'kumo':
      return kumoUploadLabels(currentIp, labels, onProgress)
    case 'videohub':
      return videohubUploadLabels(currentIp, labels)
    case 'lightware':
      return lightwareUploadLabels(currentIp, labels)
  }
}

export async function getCrosspoints(): Promise<Crosspoint[]> {
  if (!currentType || !currentIp) throw new Error('Not connected to any router')

  switch (currentType) {
    case 'kumo':
      return kumoGetCrosspoints(currentIp, currentOutputCount)
    case 'videohub':
      return videohubGetRouting(currentIp)
    case 'lightware':
      throw new Error('Lightware does not support crosspoint queries via this protocol')
  }
}

export async function setRoute(output: number, input: number): Promise<boolean> {
  if (!currentType || !currentIp) throw new Error('Not connected to any router')

  switch (currentType) {
    case 'kumo':
      // KUMO uses 1-based ports
      return kumoSetRoute(currentIp, output + 1, input + 1)
    case 'videohub':
      // Videohub uses 0-based
      return videohubSetRoute(currentIp, output, input)
    case 'lightware':
      throw new Error('Lightware routing not implemented')
  }
}
