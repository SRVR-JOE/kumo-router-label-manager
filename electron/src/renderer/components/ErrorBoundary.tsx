import React from 'react'

interface ErrorBoundaryProps {
  children: React.ReactNode
  /** Short label identifying which region of the UI this boundary guards, shown in the fallback. */
  label?: string
  /** Render a compact inline fallback instead of the full-screen one (for nested boundaries). */
  compact?: boolean
}

interface ErrorBoundaryState {
  error: Error | null
}

/**
 * Top-level safety net. Without this, a bad IPC payload or a render-time
 * exception anywhere in the tree unmounts the whole React root and leaves a
 * blank window on a field machine, with no indication of what happened or
 * any way to recover short of killing the process.
 */
export default class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props)
    this.state = { error: null }
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error }
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error(`[ErrorBoundary${this.props.label ? `:${this.props.label}` : ''}]`, error, info.componentStack)
  }

  private handleReload = () => {
    window.location.reload()
  }

  private handleDismiss = () => {
    this.setState({ error: null })
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children

    if (this.props.compact) {
      return (
        <div className="flex flex-col items-center justify-center gap-2 p-6 h-full bg-helix-bg text-helix-text">
          <div className="text-sm font-semibold text-red-400">
            {this.props.label ? `${this.props.label} failed to render` : 'Something went wrong'}
          </div>
          <div className="text-xs text-helix-text-muted max-w-md text-center break-words">{error.message}</div>
          <div className="flex gap-2 mt-1">
            <button
              onClick={this.handleDismiss}
              className="px-3 py-1 text-xs rounded border border-helix-border bg-helix-surface hover:bg-helix-surface-hover text-helix-text"
            >
              Try again
            </button>
            <button
              onClick={this.handleReload}
              className="px-3 py-1 text-xs rounded border border-helix-accent bg-helix-accent hover:bg-helix-accent-hover text-white"
            >
              Reload app
            </button>
          </div>
        </div>
      )
    }

    return (
      <div className="h-screen w-screen flex items-center justify-center bg-helix-bg text-helix-text p-6">
        <div className="max-w-lg w-full bg-helix-surface border border-helix-border rounded-lg p-6 flex flex-col gap-3 shadow-lg">
          <div className="text-base font-semibold text-red-400">
            {this.props.label ? `${this.props.label} crashed` : 'Application error'}
          </div>
          <div className="text-sm text-helix-text-muted">
            An unexpected error occurred and this part of the app could not continue. Your unsaved changes may be
            lost. You can try reloading the application below.
          </div>
          <div className="bg-helix-bg border border-helix-border rounded p-2 text-xs font-mono text-red-300 max-h-40 overflow-auto break-words">
            {error.message || String(error)}
          </div>
          <div className="flex gap-2 justify-end mt-1">
            <button
              onClick={this.handleDismiss}
              className="px-3 py-1.5 text-sm rounded border border-helix-border bg-helix-bg hover:bg-helix-surface-hover text-helix-text-muted hover:text-helix-text transition-colors"
            >
              Dismiss
            </button>
            <button
              onClick={this.handleReload}
              className="px-3 py-1.5 text-sm rounded border border-helix-accent bg-helix-accent hover:bg-helix-accent-hover text-white transition-colors"
            >
              Reload App
            </button>
          </div>
        </div>
      </div>
    )
  }
}
