import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('./net-utils', () => ({ probePort: vi.fn() }))
vi.mock('./kumo-rest', () => ({ kumoTestConnection: vi.fn() }))

import { probePort } from './net-utils'
import { kumoTestConnection } from './kumo-rest'
import { detectRouterType } from './auto-detect'

const probePortMock = vi.mocked(probePort)
const kumoTestConnectionMock = vi.mocked(kumoTestConnection)

beforeEach(() => {
  probePortMock.mockReset()
  kumoTestConnectionMock.mockReset()
})

describe('detectRouterType', () => {
  it('prefers Lightware (6107) when it responds, without probing anything else', async () => {
    probePortMock.mockResolvedValue(true)
    const result = await detectRouterType('10.0.0.5')
    expect(result).toBe('lightware')
    expect(probePortMock).toHaveBeenCalledTimes(1)
    expect(probePortMock).toHaveBeenCalledWith('10.0.0.5', 6107, expect.any(Number))
    expect(kumoTestConnectionMock).not.toHaveBeenCalled()
  })

  it('falls back to Videohub (9990) when Lightware is closed', async () => {
    probePortMock.mockImplementation(async (_ip, port) => port === 9990)
    const result = await detectRouterType('10.0.0.5')
    expect(result).toBe('videohub')
    expect(probePortMock).toHaveBeenCalledTimes(2)
    expect(kumoTestConnectionMock).not.toHaveBeenCalled()
  })

  it('falls back to KUMO REST when neither TCP port is open', async () => {
    probePortMock.mockResolvedValue(false)
    kumoTestConnectionMock.mockResolvedValue(true)
    const result = await detectRouterType('10.0.0.5')
    expect(result).toBe('kumo')
    expect(kumoTestConnectionMock).toHaveBeenCalledWith('10.0.0.5')
  })

  it('returns null when nothing responds', async () => {
    probePortMock.mockResolvedValue(false)
    kumoTestConnectionMock.mockResolvedValue(false)
    const result = await detectRouterType('10.0.0.5')
    expect(result).toBeNull()
  })

  it('checks Lightware before Videohub (probe order matters for priority)', async () => {
    const order: number[] = []
    probePortMock.mockImplementation(async (_ip, port) => {
      order.push(port)
      return false
    })
    kumoTestConnectionMock.mockResolvedValue(false)
    await detectRouterType('10.0.0.5')
    expect(order).toEqual([6107, 9990])
  })
})
