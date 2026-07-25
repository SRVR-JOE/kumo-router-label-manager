import { describe, it, expect, vi, beforeEach } from 'vitest'

// ---------------------------------------------------------------------------
// FakeSocket: a minimal net.Socket stand-in.
// Real (not fake) timers are used throughout this file — the protocol under
// test relies on a 300ms "silence detection" window, so tests pay a small
// real-time cost (a few hundred ms each) in exchange for avoiding fragile
// fake-timer/microtask interleaving with the promise-based socket code.
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

    once(event: string, cb: (...a: unknown[]) => void): this {
      const wrapper = (...a: unknown[]): void => {
        this.removeListener(event, wrapper)
        cb(...a)
      }
      return this.on(event, wrapper)
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
  videohubConnect,
  videohubDownloadLabels,
  videohubUploadLabels,
  videohubGetRouting,
  videohubSetRoute,
} from './videohub'
import type { Label } from './types'

beforeEach(() => {
  FakeSocket.instances = []
})

const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms))

/** Simulate connect + push a dump then let the 300ms silence window lapse. */
async function connectAndDump(promise: Promise<unknown>, dump: string): Promise<unknown> {
  const sock = FakeSocket.instances[0]
  sock.simulateConnected()
  await wait(10)
  sock.emit('data', Buffer.from(dump, 'utf-8'))
  await wait(350)
  return promise
}

// ---------------------------------------------------------------------------
// Real 40x40 dump adapted from tests/test_videohub_protocol.py (Python spec)
// ---------------------------------------------------------------------------
const REAL_DUMP = `PROTOCOL PREAMBLE:
Version: 2.8

VIDEOHUB DEVICE:
Device present: true
Model name: Blackmagic Smart Videohub 40 x 40
Friendly name: 4040
Unique ID: 7C2E0D07C323
Video inputs: 40
Video processing units: 0
Video outputs: 40
Video monitoring outputs: 0
Serial ports: 0

INPUT LABELS:
0 Input 1
1 Input 2

OUTPUT LABELS:
0 Output 1
1 Output 2

VIDEO OUTPUT LOCKS:
0 U
1 U

VIDEO OUTPUT ROUTING:
0 0
1 1

CONFIGURATION:
Take Mode: false

END PRELUDE:
`

describe('videohubConnect (dump parsing via public API)', () => {
  it('extracts friendly name as the device name (preferred over model name)', async () => {
    const result = await connectAndDump(videohubConnect('10.0.0.5'), REAL_DUMP)
    expect(result).toMatchObject({ success: true, deviceName: '4040', routerType: 'videohub' })
  })

  it('extracts input/output counts declared in the device block', async () => {
    const result = await connectAndDump(videohubConnect('10.0.0.5'), REAL_DUMP)
    expect(result).toMatchObject({ inputCount: 40, outputCount: 40 })
  })

  it('falls back to model name when friendly name is blank', async () => {
    const dump = REAL_DUMP.replace('Friendly name: 4040\n', '')
    const result = await connectAndDump(videohubConnect('10.0.0.5'), dump)
    expect((result as { deviceName: string }).deviceName).toBe('Blackmagic Smart Videohub 40 x 40')
  })

  it('reports failure with "No data received" when the dump is empty/whitespace', async () => {
    const promise = videohubConnect('10.0.0.5')
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    sock.emit('data', Buffer.from('   \n', 'utf-8'))
    await wait(350)
    const result = await promise
    expect(result).toMatchObject({ success: false, error: 'No data received' })
  })
})

describe('videohubDownloadLabels (label parsing + default fill-in)', () => {
  it('parses explicit labels and default-fills the remaining ports', async () => {
    const labels = (await connectAndDump(videohubDownloadLabels('10.0.0.5'), REAL_DUMP)) as Label[]
    const inputs = labels.filter((l) => l.portType === 'INPUT')
    expect(inputs).toHaveLength(40)
    expect(inputs[0].currentLabel).toBe('Input 1')
    expect(inputs[1].currentLabel).toBe('Input 2')
    // Port 3 (index 2) has no explicit label in the dump -> default fill
    expect(inputs[2].currentLabel).toBe('Input 3')
    expect(inputs[39].currentLabel).toBe('Input 40')
  })

  it('parses output labels the same way', async () => {
    const labels = (await connectAndDump(videohubDownloadLabels('10.0.0.5'), REAL_DUMP)) as Label[]
    const outputs = labels.filter((l) => l.portType === 'OUTPUT')
    expect(outputs[0].currentLabel).toBe('Output 1')
    expect(outputs[1].currentLabel).toBe('Output 2')
  })

  it('assigns 1-based port numbers from the 0-based wire indices', async () => {
    const labels = (await connectAndDump(videohubDownloadLabels('10.0.0.5'), REAL_DUMP)) as Label[]
    const firstInput = labels.find((l) => l.portType === 'INPUT')!
    expect(firstInput.portNumber).toBe(1)
  })

  it('handles a label whose text contains a literal colon (block-header lookalike)', async () => {
    const dump = `VIDEOHUB DEVICE:
Video inputs: 1
Video outputs: 0

INPUT LABELS:
0 Camera: Wide Shot

`
    const labels = (await connectAndDump(videohubDownloadLabels('10.0.0.5'), dump)) as Label[]
    expect(labels[0].currentLabel).toBe('Camera: Wide Shot')
  })
})

describe('videohubGetRouting (crosspoint parsing, 0-based)', () => {
  it('parses the routing block into 0-based output/input pairs', async () => {
    const dump = `VIDEOHUB DEVICE:
Video inputs: 4
Video outputs: 4

VIDEO OUTPUT ROUTING:
0 3
1 2
2 1
3 0

`
    const crosspoints = (await connectAndDump(videohubGetRouting('10.0.0.5'), dump)) as { output: number; input: number }[]
    expect(crosspoints).toContainEqual({ output: 0, input: 3 })
    expect(crosspoints).toContainEqual({ output: 3, input: 0 })
  })

  it('returns an empty array when there is no routing block', async () => {
    const dump = `VIDEOHUB DEVICE:
Video inputs: 2
Video outputs: 2

`
    const crosspoints = await connectAndDump(videohubGetRouting('10.0.0.5'), dump)
    expect(crosspoints).toEqual([])
  })
})

describe('videohubSetRoute', () => {
  it('sends the correctly-formatted routing command and reports ACK as success', async () => {
    const promise = videohubSetRoute('10.0.0.5', 2, 7)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    // The initial recvUntilSilence(sock, 2000) drain resolves after its own
    // 300ms silence window (no data ever arrives), well before the 2000ms cap.
    await wait(350)
    sock.emit('data', Buffer.from('ACK\n\n', 'utf-8'))
    const result = await promise
    expect(result).toBe(true)
    expect(sock.written[0]).toBe('VIDEO OUTPUT ROUTING:\n2 7\n\n')
  })

  it('reports NAK as failure', async () => {
    const promise = videohubSetRoute('10.0.0.5', 0, 1)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350)
    sock.emit('data', Buffer.from('NAK\n\n', 'utf-8'))
    const result = await promise
    expect(result).toBe(false)
  })
})

describe('videohubUploadLabels', () => {
  it('sends no data and returns a zero result when there are no changes', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT' })]
    const result = await videohubUploadLabels('10.0.0.5', labels)
    expect(result).toEqual({ successCount: 0, errorCount: 0, errors: [], results: [] })
    expect(FakeSocket.instances).toHaveLength(0)
  })

  it('builds a 0-based INPUT LABELS block and counts ACK as success', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'NEW CAM' })]
    const promise = videohubUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350) // drain initial dump read
    sock.emit('data', Buffer.from('ACK\n\n', 'utf-8'))
    const result = await promise
    expect(result.successCount).toBe(1)
    expect(sock.written[0]).toBe('INPUT LABELS:\n0 NEW CAM\n\n')
  })

  it('reports a per-port result (ok:true) for a single-port ACKed block', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'NEW CAM' })]
    const promise = videohubUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350)
    sock.emit('data', Buffer.from('ACK\n\n', 'utf-8'))
    const result = await promise
    expect(result.results).toEqual([{ portNumber: 1, portType: 'INPUT', ok: true }])
  })

  it('reports a per-port result (ok:false) for every port in a NAKed block', async () => {
    const labels: Label[] = [
      makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'NEW CAM' }),
      makeLabel({ portNumber: 2, portType: 'INPUT', currentLabel: 'OLD2', newLabel: 'NEW CAM 2' }),
    ]
    const promise = videohubUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350)
    sock.emit('data', Buffer.from('NAK\n\n', 'utf-8'))
    const result = await promise
    expect(result.results).toHaveLength(2)
    expect(result.results.every((r) => r.ok === false)).toBe(true)
    expect(result.errorCount).toBe(2)
  })

  it('strips embedded newlines from a label so block framing cannot be corrupted', async () => {
    // Videohub's LABELS block is line-oriented: "<port> <label>" per line.
    // An unsanitised "\n" in a label would inject an extra raw line, shifting
    // port attribution for every subsequent line in the block — silently
    // mislabelling a whole range. sanitizeLabel() strips CR/LF before framing.
    const labels: Label[] = [makeLabel({ portNumber: 1, portType: 'INPUT', currentLabel: 'OLD', newLabel: 'BAD\nCAM' })]
    const promise = videohubUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350)
    sock.emit('data', Buffer.from('ACK\n\n', 'utf-8'))
    await promise
    expect(sock.written[0]).toBe('INPUT LABELS:\n0 BADCAM\n\n')
  })

  it('strips carriage returns as well as newlines', async () => {
    const labels: Label[] = [makeLabel({ portNumber: 2, portType: 'OUTPUT', currentLabel: 'OLD', newLabel: 'PGM\r\nB' })]
    const promise = videohubUploadLabels('10.0.0.5', labels)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await wait(10)
    await wait(350)
    sock.emit('data', Buffer.from('ACK\n\n', 'utf-8'))
    await promise
    expect(sock.written[0]).toBe('OUTPUT LABELS:\n1 PGMB\n\n')
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
