import { describe, it, expect, vi, beforeEach } from 'vitest'

// ---------------------------------------------------------------------------
// FakeSocket: a minimal net.Socket stand-in for the LW3 {NNNN#cmd}...{ } block
// framing. Responses are emitted synchronously in-line with each command, so
// no real waiting is needed (the 10s COMMAND_TIMEOUT is never approached).
// ---------------------------------------------------------------------------
const { FakeSocket } = vi.hoisted(() => {
  class FakeSocket {
    static instances: FakeSocket[] = []
    written: string[] = []
    destroyed = false
    private connectCb: (() => void) | null = null
    private listeners: Record<string, Array<(...a: unknown[]) => void>> = {}

    constructor() {
      FakeSocket.instances.push(this)
    }

    connect(_port: number, _ip: string, cb: () => void): this {
      this.connectCb = cb
      return this
    }

    simulateConnected(): void {
      this.connectCb?.()
    }

    on(event: string, cb: (...a: unknown[]) => void): this {
      ;(this.listeners[event] ??= []).push(cb)
      return this
    }

    removeListener(event: string, cb: (...a: unknown[]) => void): this {
      this.listeners[event] = (this.listeners[event] || []).filter((l) => l !== cb)
      return this
    }

    emit(event: string, ...args: unknown[]): void {
      for (const l of (this.listeners[event] || []).slice()) l(...args)
    }

    write(data: string | Buffer): boolean {
      this.written.push(typeof data === 'string' ? data : data.toString())
      return true
    }

    destroy(): void {
      this.destroyed = true
    }
  }
  return { FakeSocket }
})

vi.mock('net', () => ({ Socket: FakeSocket }))

import {
  lightwareConnect,
  lightwareDownloadLabels,
  lightwareGetRouting,
  lightwareSetRoute,
  lightwareUploadLabels,
} from './lightware'
import type { Label } from './types'

beforeEach(() => {
  FakeSocket.instances = []
})

const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms))

/** Build an LW3 response frame: {IDSTR\r\n<lines>\r\n}\r\n */
function frame(idNum: number, lines: string[]): string {
  const idStr = String(idNum).padStart(4, '0')
  return `{${idStr}\r\n${lines.map((l) => l + '\r\n').join('')}}\r\n`
}

/**
 * Connect the socket then answer each expected LW3 command in order as the
 * driver sends it, by matching on the outgoing framed command text.
 * `responses` maps a substring of the outgoing command to the reply lines.
 */
async function driveLw3(
  promise: Promise<unknown>,
  responses: Array<{ match: string; lines: string[] }>,
): Promise<unknown> {
  const sock = FakeSocket.instances[0]
  sock.simulateConnected()
  await wait(5)

  for (const { match, lines } of responses) {
    // Wait for the next write to arrive that matches, then respond.
    let attempts = 0
    while (!sock.written.some((w) => w.includes(match)) && attempts < 20) {
      await wait(5)
      attempts++
    }
    const idx = sock.written.findIndex((w) => w.includes(match))
    // Extract the 4-digit request id from "0001#..." at the start of the write
    const idMatch = /^(\d{4})#/.exec(sock.written[idx])
    const idNum = idMatch ? parseInt(idMatch[1], 10) : 1
    sock.emit('data', Buffer.from(frame(idNum, lines), 'ascii'))
    await wait(5)
  }

  return promise
}

// ===========================================================================
// lightwareConnect — product name + port count derived from label names
// ===========================================================================

describe('lightwareConnect', () => {
  it('derives input/output counts from the highest label index seen (no PortCount props on MX2)', async () => {
    const result = await driveLw3(lightwareConnect('10.0.0.5'), [
      { match: 'GET /.ProductName', lines: ['pr /.ProductName=MX2-32x32-HDMI20-A-R'] },
      {
        match: 'GET /MEDIA/NAMES/VIDEO.*',
        lines: [
          'pw /MEDIA/NAMES/VIDEO.I1=1;Input 1',
          'pw /MEDIA/NAMES/VIDEO.I3=1;Input 3',
          'pw /MEDIA/NAMES/VIDEO.O1=1;Output 1',
          'pw /MEDIA/NAMES/VIDEO.O2=1;Output 2',
        ],
      },
    ])
    expect(result).toMatchObject({
      success: true,
      deviceName: 'MX2-32x32-HDMI20-A-R',
      inputCount: 3,
      outputCount: 2,
    })
  })

  it('reports failure when the TCP connection fails on every attempt of the shared retry policy', async () => {
    // connectSocket now retries a failed connect once (retry.ts, DEFAULT_MAX_RETRIES=2)
    // before giving up, so a hard-down device needs both attempts to fail.
    const promise = lightwareConnect('10.0.0.5')
    FakeSocket.instances[0].emit('error', new Error('ECONNREFUSED'))
    await wait(320) // let the 300ms backoff elapse so the retry attempt is made
    expect(FakeSocket.instances).toHaveLength(2)
    FakeSocket.instances[1].emit('error', new Error('ECONNREFUSED'))
    const result = await promise
    expect(result).toMatchObject({ success: false, routerType: 'lightware' })
  })

  it('recovers when the first connect attempt fails but the retry succeeds', async () => {
    const promise = lightwareConnect('10.0.0.5')
    FakeSocket.instances[0].emit('error', new Error('ECONNREFUSED'))
    await wait(320) // let the shared retry/backoff policy make its second attempt
    expect(FakeSocket.instances).toHaveLength(2)

    const retrySock = FakeSocket.instances[1]
    retrySock.simulateConnected()
    await wait(5)

    const responses = [
      { match: 'GET /.ProductName', lines: ['pr /.ProductName=MX2-8x8'] },
      { match: 'GET /MEDIA/NAMES/VIDEO.*', lines: ['pw /MEDIA/NAMES/VIDEO.I1=1;Cam 1'] },
    ]
    for (const { match, lines } of responses) {
      let attempts = 0
      while (!retrySock.written.some((w) => w.includes(match)) && attempts < 20) {
        await wait(5)
        attempts++
      }
      const idx = retrySock.written.findIndex((w) => w.includes(match))
      const idMatch = /^(\d{4})#/.exec(retrySock.written[idx])
      const idNum = idMatch ? parseInt(idMatch[1], 10) : 1
      retrySock.emit('data', Buffer.from(frame(idNum, lines), 'ascii'))
      await wait(5)
    }

    const result = await promise
    expect(result).toMatchObject({ success: true, deviceName: 'MX2-8x8' })
  })
})

// ===========================================================================
// lightwareDownloadLabels — the "optional N; page prefix" regex tolerance
// ===========================================================================

describe('lightwareDownloadLabels label regex (page-prefix tolerance)', () => {
  it('parses labels WITH the "N;" page prefix', async () => {
    const labels = (await driveLw3(lightwareDownloadLabels('10.0.0.5'), [
      {
        match: 'GET /MEDIA/NAMES/VIDEO.*',
        lines: [
          'pw /MEDIA/NAMES/VIDEO.I1=1;Camera 1',
          'pw /MEDIA/NAMES/VIDEO.O1=2;Monitor 1',
        ],
      },
    ])) as Label[]
    const input1 = labels.find((l) => l.portType === 'INPUT' && l.portNumber === 1)!
    const output1 = labels.find((l) => l.portType === 'OUTPUT' && l.portNumber === 1)!
    expect(input1.currentLabel).toBe('Camera 1')
    expect(output1.currentLabel).toBe('Monitor 1')
  })

  it('parses labels WITHOUT any page prefix (plain name fallback)', async () => {
    const labels = (await driveLw3(lightwareDownloadLabels('10.0.0.5'), [
      {
        match: 'GET /MEDIA/NAMES/VIDEO.*',
        lines: ['pw /MEDIA/NAMES/VIDEO.I1=Camera Plain'],
      },
    ])) as Label[]
    const input1 = labels.find((l) => l.portType === 'INPUT' && l.portNumber === 1)!
    expect(input1.currentLabel).toBe('Camera Plain')
  })

  it('does not misinterpret a label that starts with digits followed by a non-semicolon as a page prefix', async () => {
    // "42 Camera" has no semicolon, so the optional (?:\d+;)? group must NOT
    // consume the leading digits — the whole string is the label.
    const labels = (await driveLw3(lightwareDownloadLabels('10.0.0.5'), [
      { match: 'GET /MEDIA/NAMES/VIDEO.*', lines: ['pw /MEDIA/NAMES/VIDEO.I1=42 Camera'] },
    ])) as Label[]
    const input1 = labels.find((l) => l.portType === 'INPUT' && l.portNumber === 1)!
    expect(input1.currentLabel).toBe('42 Camera')
  })

  it('default-fills labels for ports that have no explicit name below the max seen index', async () => {
    const labels = (await driveLw3(lightwareDownloadLabels('10.0.0.5'), [
      {
        match: 'GET /MEDIA/NAMES/VIDEO.*',
        lines: ['pw /MEDIA/NAMES/VIDEO.I2=1;Camera 2'], // I1 never named, but I2 implies inputCount>=2
      },
    ])) as Label[]
    const input1 = labels.find((l) => l.portType === 'INPUT' && l.portNumber === 1)!
    expect(input1.currentLabel).toBe('Input 1')
  })

  it('returns an empty label set when the device reports no names at all', async () => {
    const labels = (await driveLw3(lightwareDownloadLabels('10.0.0.5'), [
      { match: 'GET /MEDIA/NAMES/VIDEO.*', lines: [] },
    ])) as Label[]
    expect(labels).toEqual([])
  })
})

// ===========================================================================
// lightwareGetRouting — DestinationConnectionStatus semicolon list
// ===========================================================================

describe('lightwareGetRouting', () => {
  it('parses a semicolon-separated I{n} list into 0-based crosspoints', async () => {
    const crosspoints = (await driveLw3(lightwareGetRouting('10.0.0.5'), [
      {
        match: 'GETALL /MEDIA/XP/VIDEO',
        lines: ['pw /MEDIA/XP/VIDEO.DestinationConnectionStatus=I1;I3;I2'],
      },
    ])) as { output: number; input: number }[]
    expect(crosspoints).toEqual([
      { output: 0, input: 0 },
      { output: 1, input: 2 },
      { output: 2, input: 1 },
    ])
  })

  it('returns an empty array when the status line is absent', async () => {
    const crosspoints = await driveLw3(lightwareGetRouting('10.0.0.5'), [
      { match: 'GETALL /MEDIA/XP/VIDEO', lines: ['pE something went wrong'] },
    ])
    expect(crosspoints).toEqual([])
  })

  it('skips malformed entries in the status list rather than throwing', async () => {
    const crosspoints = (await driveLw3(lightwareGetRouting('10.0.0.5'), [
      {
        match: 'GETALL /MEDIA/XP/VIDEO',
        lines: ['pw /MEDIA/XP/VIDEO.DestinationConnectionStatus=I1;NC;I5'],
      },
    ])) as { output: number; input: number }[]
    expect(crosspoints).toEqual([
      { output: 0, input: 0 },
      { output: 2, input: 4 },
    ])
  })
})

// ===========================================================================
// lightwareSetRoute — CALL .../switch(...) success/error detection
// ===========================================================================

describe('lightwareSetRoute', () => {
  it('sends a 1-based CALL switch command for 0-based output/input args', async () => {
    const promise = lightwareSetRoute('10.0.0.5', 2, 5) // output idx2 -> O3, input idx5 -> I6
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    expect(sock.written[0]).toContain('CALL /MEDIA/XP/VIDEO:switch(I6:O3)')
    sock.emit('data', Buffer.from(frame(1, ['mO /MEDIA/XP/VIDEO:switch=OK']), 'ascii'))
    expect(await promise).toBe(true)
  })

  it('returns false on an LW3 error line', async () => {
    const promise = lightwareSetRoute('10.0.0.5', 0, 0)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    sock.emit('data', Buffer.from(frame(1, ['pE invalid crosspoint']), 'ascii'))
    expect(await promise).toBe(false)
  })

  it('returns false when the connection fails outright (both attempts of the retry policy)', async () => {
    const promise = lightwareSetRoute('10.0.0.5', 0, 0)
    FakeSocket.instances[0].emit('error', new Error('down'))
    await wait(320)
    expect(FakeSocket.instances).toHaveLength(2)
    FakeSocket.instances[1].emit('error', new Error('down'))
    expect(await promise).toBe(false)
  })
})

// ===========================================================================
// lightwareUploadLabels — semicolon sanitisation (label injection prevention)
// ===========================================================================

describe('lightwareUploadLabels label sanitisation', () => {
  it('strips semicolons from the label before building the SET command', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'CAM;1;evil' })]
    const promise = lightwareUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    expect(sock.written[0]).toBe('0001#SET /MEDIA/NAMES/VIDEO.I1=1;CAM1evil\r\n')
    sock.emit('data', Buffer.from(frame(1, ['pw /MEDIA/NAMES/VIDEO.I1=1;CAM1evil']), 'ascii'))
    const result = await promise
    expect(result.successCount).toBe(1)
  })

  it('does NOT sanitise a leading/trailing quote or other shell-adjacent characters (only ";" is stripped)', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'CAM "A"' })]
    const promise = lightwareUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    expect(sock.written[0]).toContain('CAM "A"')
    sock.emit('data', Buffer.from(frame(1, ['pw ...=OK']), 'ascii'))
    await promise
  })

  it('truncates overlong labels to 255 characters', async () => {
    const longLabel = 'X'.repeat(300)
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: longLabel })]
    const promise = lightwareUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    const sentLabel = sock.written[0].split('=1;')[1].replace('\r\n', '')
    expect(sentLabel).toHaveLength(255)
    sock.emit('data', Buffer.from(frame(1, ['pw ...=OK']), 'ascii'))
    await promise
  })

  it('counts an LW3 error response as a failure with a descriptive message', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'NEW' })]
    const promise = lightwareUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(5)
    let attempts = 0
    while (sock.written.length === 0 && attempts < 20) {
      await wait(5)
      attempts++
    }
    sock.emit('data', Buffer.from(frame(1, ['pE bad request']), 'ascii'))
    const result = await promise
    expect(result.errorCount).toBe(1)
    expect(result.errors[0]).toContain('INPUT 1')
  })

  it('sends nothing and returns a zero result when there are no changes', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT' })]
    const result = await lightwareUploadLabels('10.0.0.5', labels)
    expect(result).toEqual({ successCount: 0, errorCount: 0, errors: [], results: [] })
    expect(FakeSocket.instances).toHaveLength(0)
  })

  it('reports connection failure as an error for every pending change, with one result entry per port', async () => {
    const promise = lightwareUploadLabels('10.0.0.5', [
      makeLabel({ portNumber: 1, portType: 'INPUT', newLabel: 'A' }),
      makeLabel({ portNumber: 2, portType: 'INPUT', newLabel: 'B' }),
    ])
    FakeSocket.instances[0].emit('error', new Error('down'))
    await wait(320) // the shared retry/backoff policy makes a second connect attempt
    expect(FakeSocket.instances).toHaveLength(2)
    FakeSocket.instances[1].emit('error', new Error('down'))
    const result = await promise
    expect(result.errorCount).toBe(2)
    expect(result.successCount).toBe(0)
    expect(result.results).toHaveLength(2)
    expect(result.results.every((r) => r.ok === false)).toBe(true)
  })
})

function makeLabel(overrides: Partial<Label>): Label {
  return {
    portNumber: 1,
    portType: 'INPUT',
    currentLabel: 'Input 1',
    newLabel: null,
    currentLabelLine2: '',
    newLabelLine2: null,
    currentColor: 4,
    newColor: null,
    notes: '',
    ...overrides,
  }
}
