// Single retry/backoff policy shared by every protocol adapter (HTTP and raw
// socket paths alike). Ported from the tuned Python implementation at
// src/agents/api_agent/router_protocols.py (~line 339-352):
//   MAX_RETRIES = 2
//   RETRY_BACKOFF_BASE = 0.3s
//   RETRY_BACKOFF_MULTIPLIER = 2
// i.e. two total attempts with a single 300ms backoff between them — tuned
// against real KUMO/Videohub/Lightware hardware on a LAN, not a guess.
//
// Deliberately NOT applied to mutating socket round-trips (Videohub
// ACK/NAK label writes, Lightware SET/CALL commands) where a retry after an
// ambiguous timeout could double-send a command with no way to confirm
// whether the first attempt actually landed. It IS applied to:
//   - kumo-rest.ts fetchWithTimeout (covers both GET and SET — safe because
//     re-sending the same "set this param to X" HTTP request is idempotent)
//   - videohub.ts / lightware.ts TCP connect (safe — establishing a socket
//     has no device-visible side effect)

export const DEFAULT_MAX_RETRIES = 2
export const DEFAULT_BACKOFF_BASE_MS = 300
export const DEFAULT_BACKOFF_MULTIPLIER = 2

export interface RetryOptions<T> {
  maxRetries?: number
  backoffBaseMs?: number
  backoffMultiplier?: number
  /** Return true if a successfully-resolved value should still be retried (e.g. a non-2xx HTTP response). */
  isRetryableResult?: (result: T) => boolean
  /** Return false to stop retrying immediately for a given error (defaults to always retryable, matching the Python client). */
  isRetryableError?: (err: unknown) => boolean
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/**
 * Runs `fn` with exponential backoff on failure. "Failure" means either the
 * call threw, or (if `isRetryableResult` is supplied) it resolved to a value
 * that should be treated as retryable, e.g. a non-ok HTTP Response.
 *
 * On exhausting all attempts: if the last attempt produced a resolved (but
 * retryable) result, that result is returned rather than thrown — mirroring
 * the Python client, which returns the last response as-is after retries run
 * out rather than synthesizing an error.
 */
export async function withRetry<T>(fn: (attempt: number) => Promise<T>, opts: RetryOptions<T> = {}): Promise<T> {
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES
  const base = opts.backoffBaseMs ?? DEFAULT_BACKOFF_BASE_MS
  const multiplier = opts.backoffMultiplier ?? DEFAULT_BACKOFF_MULTIPLIER

  let lastError: unknown
  let lastResult: T | undefined
  let haveResult = false

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const result = await fn(attempt)
      if (opts.isRetryableResult && opts.isRetryableResult(result)) {
        lastResult = result
        haveResult = true
      } else {
        return result
      }
    } catch (e) {
      lastError = e
      haveResult = false
      if (opts.isRetryableError && !opts.isRetryableError(e)) throw e
    }

    if (attempt < maxRetries - 1) {
      await sleep(base * Math.pow(multiplier, attempt))
    }
  }

  if (haveResult) return lastResult as T
  throw lastError
}
