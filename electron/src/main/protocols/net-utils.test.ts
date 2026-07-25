import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// Mock the 'net' module so no real socket is ever opened.
// FakeSocket captures the connect() callback so tests can drive
// success/failure/timeout deterministically instead of racing real I/O.
// Declared via vi.hoisted so it's available inside the hoisted vi.mock factory.
// Note: cannot import 'events' here since vi.hoisted() code runs before
// regular imports are initialized — so we implement a minimal emitter inline.
const { FakeSocket } = vi.hoisted(() => {
  class FakeSocket {
    static instances: FakeSocket[] = []
    destroyed = false
    connectArgs: [number, string] | null = null
    private connectCb: (() => void) | null = null
    private errorHandlers: Array<(err: Error) => void> = []

    constructor() {
      FakeSocket.instances.push(this)
    }

    on(event: string, handler: (...args: unknown[]) => void): this {
      if (event === 'error') this.errorHandlers.push(handler as (err: Error) => void)
      return this
    }

    emit(event: string, ...args: unknown[]): void {
      if (event === 'error') {
        for (const h of this.errorHandlers) h(args[0] as Error)
      }
    }

    connect(port: number, ip: string, cb: () => void): this {
      this.connectArgs = [port, ip]
      this.connectCb = cb
      return this
    }

    /** Test helper: simulate a successful TCP connection. */
    simulateConnected(): void {
      this.connectCb?.()
    }

    /** Test helper: simulate a connection error. */
    simulateError(err: Error): void {
      this.emit('error', err)
    }

    destroy(): void {
      this.destroyed = true
    }
  }
  return { FakeSocket }
})

vi.mock('net', () => ({ Socket: FakeSocket }))

import { probePort } from './net-utils'

beforeEach(() => {
  FakeSocket.instances = []
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('probePort', () => {
  it('resolves true when the socket connects successfully', async () => {
    const promise = probePort('10.0.0.5', 6107, 1000)
    const sock = FakeSocket.instances[0]
    expect(sock.connectArgs).toEqual([6107, '10.0.0.5'])
    sock.simulateConnected()
    await expect(promise).resolves.toBe(true)
  })

  it('destroys the socket after a successful connect', async () => {
    const promise = probePort('10.0.0.5', 6107, 1000)
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await promise
    expect(sock.destroyed).toBe(true)
  })

  it('resolves false (never rejects) on a socket error', async () => {
    const promise = probePort('10.0.0.5', 9990, 1000)
    const sock = FakeSocket.instances[0]
    sock.simulateError(new Error('ECONNREFUSED'))
    await expect(promise).resolves.toBe(false)
  })

  it('resolves false when the connection attempt times out', async () => {
    const promise = probePort('10.0.0.5', 80, 500)
    // Never call simulateConnected() — let the timeout fire.
    await vi.advanceTimersByTimeAsync(500)
    await expect(promise).resolves.toBe(false)
  })

  it('destroys the socket on timeout', async () => {
    const promise = probePort('10.0.0.5', 80, 500)
    const sock = FakeSocket.instances[0]
    await vi.advanceTimersByTimeAsync(500)
    await promise
    expect(sock.destroyed).toBe(true)
  })

  it('does not resolve before the timeout or a connect/error event', async () => {
    let settled = false
    const promise = probePort('10.0.0.5', 80, 1000).then((v) => {
      settled = true
      return v
    })
    await vi.advanceTimersByTimeAsync(999)
    expect(settled).toBe(false)
    // clean up
    const sock = FakeSocket.instances[0]
    sock.simulateConnected()
    await promise
  })
})
