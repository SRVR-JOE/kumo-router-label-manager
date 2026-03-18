// Error hierarchy for Helix app

export class HelixError extends Error {
  constructor(message: string, public code: string = 'HELIX_ERROR') {
    super(message)
    this.name = 'HelixError'
  }
}

export class ConnectionError extends HelixError {
  constructor(message: string, public ip?: string) {
    super(message, 'CONNECTION_ERROR')
    this.name = 'ConnectionError'
  }
}

export class ProtocolError extends HelixError {
  constructor(message: string, public protocol?: string) {
    super(message, 'PROTOCOL_ERROR')
    this.name = 'ProtocolError'
  }
}

export class TimeoutError extends HelixError {
  constructor(message: string, public timeoutMs?: number) {
    super(message, 'TIMEOUT_ERROR')
    this.name = 'TimeoutError'
  }
}

export class FileError extends HelixError {
  constructor(message: string, public filePath?: string) {
    super(message, 'FILE_ERROR')
    this.name = 'FileError'
  }
}

export class ValidationError extends HelixError {
  constructor(message: string) {
    super(message, 'VALIDATION_ERROR')
    this.name = 'ValidationError'
  }
}
