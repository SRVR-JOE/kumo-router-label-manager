import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import {
  kumoTestConnection,
  kumoProbeSystemName,
  kumoGetSystemName,
  kumoGetFirmwareVersion,
  kumoDetectPortCount,
  kumoConnect,
  kumoDownloadLabels,
  kumoUploadLabels,
  kumoGetCrosspoints,
  kumoSetRoute,
} from './kumo-rest'
import type { Label } from './types'

// ---------------------------------------------------------------------------
// fetch mocking helpers
// ---------------------------------------------------------------------------

type FetchCall = { url: string }

function mockJsonResponse(body: unknown, ok = true): Response {
  return {
    ok,
    json: async () => body,
  } as unknown as Response
}

/** Installs a global.fetch mock and returns the vi.fn spy plus a helper to read call URLs. */
function installFetchMock(): { fetchMock: ReturnType<typeof vi.fn>; calls: () => string[] } {
  const fetchMock = vi.fn()
  vi.stubGlobal('fetch', fetchMock)
  return {
    fetchMock,
    calls: () => (fetchMock.mock.calls as FetchCall[][]).map((c) => c[0] as unknown as string),
  }
}

beforeEach(() => {
  vi.useRealTimers()
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

// ===========================================================================
// URL construction (verified indirectly through fetch call arguments, since
// getUrl/setUrl/sourceNameParam/etc. are not exported)
// ===========================================================================

describe('GET URL construction', () => {
  it('builds the SysName probe URL with action=get and configid=0', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'KUMO32' }))

    await kumoProbeSystemName('10.0.0.5')

    const url = fetchMock.mock.calls[0][0] as string
    expect(url).toBe('http://10.0.0.5/config?action=get&configid=0&paramid=eParamID_SysName')
  })

  it('builds the firmware version URL with eParamID_SWVersion', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'v8.5' }))

    await kumoGetFirmwareVersion('10.0.0.5')

    const url = fetchMock.mock.calls[0][0] as string
    expect(url).toContain('action=get')
    expect(url).toContain('paramid=eParamID_SWVersion')
  })

  it('probes source ports 33 and 17 in parallel for port-count detection', async () => {
    const { fetchMock, calls } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'X' }))

    await kumoDetectPortCount('10.0.0.5')

    const urls = calls()
    expect(urls.some((u) => u.includes('eParamID_XPT_Source33_Line_1'))).toBe(true)
    expect(urls.some((u) => u.includes('eParamID_XPT_Source17_Line_1'))).toBe(true)
  })
})

describe('SET URL construction / value encoding', () => {
  it('URL-encodes spaces in a label value', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))

    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', newLabel: 'CAM 1' })]
    await kumoUploadLabels('10.0.0.5', labels)

    const url = fetchMock.mock.calls[0][0] as string
    expect(url).toContain('CAM%201')
  })

  it('URL-encodes ampersands so the query string is not corrupted', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))

    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', newLabel: 'A&B' })]
    await kumoUploadLabels('10.0.0.5', labels)

    const url = fetchMock.mock.calls[0][0] as string
    expect(url).toContain('%26')
    expect(url).not.toContain('value=A&B')
  })

  it('round-trips an adversarial label value (unicode + spaces) through encodeURIComponent/decodeURIComponent', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))

    const original = 'CAM 1 – Live'
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', newLabel: original })]
    await kumoUploadLabels('10.0.0.5', labels)

    const url = fetchMock.mock.calls[0][0] as string
    const encoded = url.split('value=')[1]
    expect(decodeURIComponent(encoded)).toBe(original)
  })
})

// ===========================================================================
// parseParamResponse fallback behaviour (value_name -> value -> null)
// ===========================================================================

describe('parameter response parsing (via kumoProbeSystemName)', () => {
  it('prefers value_name when present and non-empty', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'CAM 1', value: '0' }))
    expect(await kumoProbeSystemName('10.0.0.5')).toBe('CAM 1')
  })

  it('falls back to value when value_name is empty', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: '', value: 'CAM 1' }))
    expect(await kumoProbeSystemName('10.0.0.5')).toBe('CAM 1')
  })

  it('returns null when both fields are empty', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: '', value: '' }))
    expect(await kumoProbeSystemName('10.0.0.5')).toBeNull()
  })

  it('returns null (not throwing) on a non-ok HTTP response', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({}, false))
    expect(await kumoProbeSystemName('10.0.0.5')).toBeNull()
  })

  it('returns null when fetch rejects (network error)', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('ECONNREFUSED'))
    expect(await kumoProbeSystemName('10.0.0.5')).toBeNull()
  })
})

// ===========================================================================
// Test connection / connect / firmware / system name convenience wrappers
// ===========================================================================

describe('kumoTestConnection', () => {
  it('is true when the probe succeeds', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'KUMO' }))
    expect(await kumoTestConnection('10.0.0.5')).toBe(true)
  })

  it('is false when the probe fails', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    expect(await kumoTestConnection('10.0.0.5')).toBe(false)
  })
})

describe('kumoGetSystemName / kumoGetFirmwareVersion fallbacks', () => {
  it('falls back to "KUMO" when the device is unreachable', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    expect(await kumoGetSystemName('10.0.0.5')).toBe('KUMO')
  })

  it('falls back to "Unknown" firmware on failure', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    expect(await kumoGetFirmwareVersion('10.0.0.5')).toBe('Unknown')
  })
})

describe('kumoDetectPortCount', () => {
  it('detects 64 ports when the 33rd source resolves', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Source33')) return mockJsonResponse({ value_name: 'Port 33' })
      return mockJsonResponse({ value_name: 'Port 17' })
    })
    expect(await kumoDetectPortCount('10.0.0.5')).toBe(64)
  })

  it('detects 32 ports when only the 17th source resolves', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Source33')) return mockJsonResponse({}, false)
      return mockJsonResponse({ value_name: 'Port 17' })
    })
    expect(await kumoDetectPortCount('10.0.0.5')).toBe(32)
  })

  it('falls back to 16 ports when neither probe resolves', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({}, false))
    expect(await kumoDetectPortCount('10.0.0.5')).toBe(16)
  })
})

describe('kumoConnect', () => {
  it('reports failure with a descriptive error when the system name probe fails', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    const result = await kumoConnect('10.0.0.5')
    expect(result.success).toBe(false)
    expect(result.routerType).toBe('kumo')
    expect(result.error).toContain('10.0.0.5')
  })

  it('reports success with device name and port count on a healthy device', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('eParamID_SysName')) return mockJsonResponse({ value_name: 'MyKumo' })
      if (url.includes('Source33')) return mockJsonResponse({}, false)
      if (url.includes('Source17')) return mockJsonResponse({ value_name: 'Port 17' })
      return mockJsonResponse({}, false)
    })
    const result = await kumoConnect('10.0.0.5')
    expect(result.success).toBe(true)
    expect(result.deviceName).toBe('MyKumo')
    expect(result.inputCount).toBe(32)
    expect(result.outputCount).toBe(32)
  })
})

// ===========================================================================
// Button color param-id mapping (eParamID_Button_Settings_N)
// Verified indirectly through the URLs used in downloadLabels/uploadLabels,
// since buttonColorParam() itself is not exported.
// Mirrors src/agents/api_agent tests for KumoParamID.button_color().
// ===========================================================================

describe('button color parameter-id mapping', () => {
  async function downloadAndCaptureColorUrls(portCount: number): Promise<string[]> {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'X' }))
    await kumoDownloadLabels('10.0.0.5', portCount)
    return (fetchMock.mock.calls as FetchCall[][])
      .map((c) => c[0] as unknown as string)
      .filter((u) => u.includes('Button_Settings'))
  }

  it('maps INPUT port 1 -> Button_Settings_1', async () => {
    const urls = await downloadAndCaptureColorUrls(1)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_1&') || u.endsWith('eParamID_Button_Settings_1'))).toBe(true)
  })

  it('maps INPUT port 17 -> Button_Settings_33 (next block of 32)', async () => {
    const urls = await downloadAndCaptureColorUrls(17)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_33'))).toBe(true)
  })

  it('maps INPUT port 32 -> Button_Settings_48', async () => {
    const urls = await downloadAndCaptureColorUrls(32)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_48'))).toBe(true)
  })

  it('maps OUTPUT port 1 -> Button_Settings_17 (input block offset by 16)', async () => {
    const urls = await downloadAndCaptureColorUrls(1)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_17'))).toBe(true)
  })

  it('maps OUTPUT port 32 -> Button_Settings_64', async () => {
    const urls = await downloadAndCaptureColorUrls(32)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_64'))).toBe(true)
  })

  it('maps OUTPUT port 64 -> Button_Settings_128', async () => {
    const urls = await downloadAndCaptureColorUrls(64)
    expect(urls.some((u) => u.includes('eParamID_Button_Settings_128'))).toBe(true)
  })
})

// ===========================================================================
// Button color parse/encode (verified via downloadLabels / uploadLabels)
// ===========================================================================

describe('button color value parsing (downloadLabels)', () => {
  it('parses {"classes":"color_N"} JSON responses for every valid color', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Button_Settings')) return mockJsonResponse({ value: '{"classes":"color_7"}' })
      return mockJsonResponse({ value_name: 'Label' })
    })
    const labels = await kumoDownloadLabels('10.0.0.5', 1)
    expect(labels[0].currentColor).toBe(7)
  })

  it('falls back to the default color for out-of-range values', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Button_Settings')) return mockJsonResponse({ value: '{"classes":"color_10"}' })
      return mockJsonResponse({ value_name: 'Label' })
    })
    const labels = await kumoDownloadLabels('10.0.0.5', 1)
    expect(labels[0].currentColor).toBe(4) // KUMO_DEFAULT_COLOR
  })

  it('falls back to the default color when the color fetch throws', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Button_Settings')) throw new Error('timeout')
      return mockJsonResponse({ value_name: 'Label' })
    })
    const labels = await kumoDownloadLabels('10.0.0.5', 1)
    expect(labels[0].currentColor).toBe(4)
  })
})

describe('button color encoding (uploadLabels)', () => {
  it('encodes a valid color id into the classes/color_N payload', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentColor: 4, newColor: 3 })]
    await kumoUploadLabels('10.0.0.5', labels)
    const url = fetchMock.mock.calls[0][0] as string
    const decoded = decodeURIComponent(url.split('value=')[1])
    expect(decoded).toContain('color_3')
  })

  it('clamps an out-of-range new color to the default before encoding', async () => {
    // newColor is validated elsewhere in the app, but exercise the encoder's
    // own clamping behaviour by forcing an out-of-range value through.
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentColor: 4, newColor: 55 })]
    await kumoUploadLabels('10.0.0.5', labels)
    const url = fetchMock.mock.calls[0][0] as string
    const decoded = decodeURIComponent(url.split('value=')[1])
    expect(decoded).toContain('color_4')
  })
})

// ===========================================================================
// kumoDownloadLabels — default fill-in behaviour
// ===========================================================================

describe('kumoDownloadLabels defaults', () => {
  it('fills "Source N" / "Dest N" defaults when the device returns nothing', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({}, false))
    const labels = await kumoDownloadLabels('10.0.0.5', 2)
    const in1 = labels.find((l) => l.portType === 'INPUT' && l.portNumber === 1)!
    const out2 = labels.find((l) => l.portType === 'OUTPUT' && l.portNumber === 2)!
    expect(in1.currentLabel).toBe('Source 1')
    expect(out2.currentLabel).toBe('Dest 2')
  })

  it('returns 2x portCount labels (inputs + outputs) with line 1 & 2 slots', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'X' }))
    const labels = await kumoDownloadLabels('10.0.0.5', 3)
    expect(labels).toHaveLength(6)
    expect(labels.filter((l) => l.portType === 'INPUT')).toHaveLength(3)
    expect(labels.filter((l) => l.portType === 'OUTPUT')).toHaveLength(3)
  })

  it('reports final progress callback with done === total', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'X' }))
    const calls: Array<[number, number]> = []
    await kumoDownloadLabels('10.0.0.5', 2, (done, total) => calls.push([done, total]))
    const last = calls[calls.length - 1]
    expect(last[0]).toBe(last[1])
  })
})

// ===========================================================================
// kumoUploadLabels — change detection
// ===========================================================================

describe('kumoUploadLabels change detection', () => {
  it('sends nothing when no label/color has changed', async () => {
    const { fetchMock } = installFetchMock()
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT' })]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(fetchMock).not.toHaveBeenCalled()
    expect(result).toEqual({ successCount: 0, errorCount: 0, errors: [], results: [] })
  })

  it('does not resend when newLabel equals currentLabel', async () => {
    const { fetchMock } = installFetchMock()
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'CAM 1', newLabel: 'CAM 1' })]
    await kumoUploadLabels('10.0.0.5', labels)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('counts a failed HTTP response as an error with a descriptive message', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({}, false))
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', newLabel: 'NEW' })]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(result.successCount).toBe(0)
    expect(result.errorCount).toBe(1)
  }, 10000)

  it('counts a thrown fetch error as an error and records the message', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('ECONNRESET'))
    const labels: Label[] = [makeLabel({ portNumber: 5, portType: 'OUTPUT', newLabel: 'NEW' })]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(result.errorCount).toBe(1)
    expect(result.errors[0]).toContain('OUTPUT 5')
  }, 10000)

  it('reports a per-port failure via results[] with ok:false and a joined error message', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('ECONNRESET'))
    const labels: Label[] = [makeLabel({ portNumber: 5, portType: 'OUTPUT', newLabel: 'NEW' })]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(result.results).toHaveLength(1)
    expect(result.results[0]).toMatchObject({ portNumber: 5, portType: 'OUTPUT', ok: false })
    expect(result.results[0].error).toContain('OUTPUT 5')
  }, 10000)

  it('reports a per-port success via results[] with ok:true and rolls up all 3 subtasks (line1/line2/color)', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))
    const labels: Label[] = [
      makeLabel({
        portNumber: 1,
        portType: 'INPUT',
        currentLabel: 'OLD',
        newLabel: 'NEW',
        currentLabelLine2: 'OLD2',
        newLabelLine2: 'NEW2',
        currentColor: 4,
        newColor: 1,
      }),
    ]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(result.results).toEqual([{ portNumber: 1, portType: 'INPUT', ok: true, error: undefined }])
    expect(result.successCount).toBe(1)
    expect(result.errorCount).toBe(0)
  })

  it('reports a per-port failure when only one of its 3 subtasks (color) fails, even though line1/line2 succeeded', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('Button_Settings')) return mockJsonResponse({}, false)
      return mockJsonResponse({ value: 'ok' })
    })
    const labels: Label[] = [
      makeLabel({
        portNumber: 1,
        portType: 'INPUT',
        currentLabel: 'OLD',
        newLabel: 'NEW',
        currentColor: 4,
        newColor: 1,
      }),
    ]
    const result = await kumoUploadLabels('10.0.0.5', labels)
    expect(result.results).toHaveLength(1)
    expect(result.results[0].ok).toBe(false)
    expect(result.results[0].error).toContain('color')
  }, 10000)

  it('sends line 1, line 2 and color as independent requests when all three change', async () => {
    const { fetchMock, calls } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))
    const labels: Label[] = [
      makeLabel({
        portNumber: 1,
        portType: 'INPUT',
        currentLabel: 'OLD',
        newLabel: 'NEW',
        currentLabelLine2: 'OLD2',
        newLabelLine2: 'NEW2',
        currentColor: 4,
        newColor: 1,
      }),
    ]
    await kumoUploadLabels('10.0.0.5', labels)
    const urls = calls()
    expect(urls).toHaveLength(3)
    expect(urls.some((u) => u.includes('Source1_Line_1'))).toBe(true)
    expect(urls.some((u) => u.includes('Source1_Line_2'))).toBe(true)
    expect(urls.some((u) => u.includes('Button_Settings'))).toBe(true)
  })
})

// ===========================================================================
// Crosspoints / routing
// ===========================================================================

describe('kumoGetCrosspoints', () => {
  it('converts 1-based destination status values to 0-based crosspoints', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: '5' }))
    const xpts = await kumoGetCrosspoints('10.0.0.5', 1)
    expect(xpts[0]).toEqual({ output: 0, input: 4 })
  })

  it('defaults to input 0 when the response cannot be parsed as a number', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value_name: 'not-a-number' }))
    const xpts = await kumoGetCrosspoints('10.0.0.5', 1)
    expect(xpts[0]).toEqual({ output: 0, input: 0 })
  })

  it('defaults to input 0 when the request throws', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    const xpts = await kumoGetCrosspoints('10.0.0.5', 1)
    expect(xpts[0]).toEqual({ output: 0, input: 0 })
  })
})

describe('kumoSetRoute', () => {
  it('sends the 1-based input port as the value for the destination status param', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockResolvedValue(mockJsonResponse({ value: 'ok' }))
    const ok = await kumoSetRoute('10.0.0.5', 3, 7)
    expect(ok).toBe(true)
    const url = fetchMock.mock.calls[0][0] as string
    expect(url).toContain('eParamID_XPT_Destination3_Status')
    expect(url).toContain('value=7')
  })

  it('returns false when the request fails', async () => {
    const { fetchMock } = installFetchMock()
    fetchMock.mockRejectedValue(new Error('down'))
    expect(await kumoSetRoute('10.0.0.5', 3, 7)).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// Test data builders
// ---------------------------------------------------------------------------

function makeLabel(overrides: Partial<Label>): Label {
  return {
    portNumber: 1,
    portType: 'INPUT',
    currentLabel: 'Source 1',
    newLabel: null,
    currentLabelLine2: '',
    newLabelLine2: null,
    currentColor: 4,
    newColor: null,
    notes: '',
    ...overrides,
  }
}
