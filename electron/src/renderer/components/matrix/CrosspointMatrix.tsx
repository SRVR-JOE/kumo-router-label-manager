import React, { useEffect, useState, useRef, useCallback } from 'react'
import { useRouterStore } from '../../stores/router-store'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { DialogWrapper } from '../router/ConnectDialog'
import { KUMO_COLORS } from '../../theme/colors'

interface Crosspoint {
  output: number
  input: number
}

export default function CrosspointMatrix() {
  const { closeDialog, showToast } = useUIStore()
  const router = useRouterStore()
  const labels = useLabelsStore()
  const [crosspoints, setCrosspoints] = useState<Crosspoint[]>([])
  const [loading, setLoading] = useState(true)
  const canvasRef = useRef<HTMLCanvasElement>(null)

  const inputCount = router.inputCount
  const outputCount = router.outputCount

  const inputLabels = labels.labels.filter(l => l.portType === 'INPUT').sort((a, b) => a.portNumber - b.portNumber)
  const outputLabels = labels.labels.filter(l => l.portType === 'OUTPUT').sort((a, b) => a.portNumber - b.portNumber)

  useEffect(() => {
    loadCrosspoints()
  }, [])

  const loadCrosspoints = async () => {
    setLoading(true)
    const xpts = await window.helix.router.getCrosspoints() as Crosspoint[]
    setCrosspoints(xpts)
    setLoading(false)
  }

  const handleRoute = async (output: number, input: number) => {
    const ok = await window.helix.router.setRoute(output, input) as boolean
    if (ok) {
      setCrosspoints(prev => {
        const filtered = prev.filter(x => x.output !== output)
        return [...filtered, { output, input }]
      })
      showToast(`Route: Input ${input + 1} -> Output ${output + 1}`, 'success')
    } else {
      showToast('Route failed', 'error')
    }
  }

  // Build routing map
  const routeMap = new Map<number, number>()
  for (const xpt of crosspoints) {
    routeMap.set(xpt.output, xpt.input)
  }

  const CELL = 28
  const LABEL_W = 100
  const LABEL_H = 60

  // Draw canvas
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas || loading) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const w = LABEL_W + inputCount * CELL
    const h = LABEL_H + outputCount * CELL
    canvas.width = w
    canvas.height = h

    ctx.fillStyle = 'rgb(30, 25, 40)'
    ctx.fillRect(0, 0, w, h)

    // Input labels (top)
    ctx.save()
    ctx.font = '10px Consolas, monospace'
    ctx.fillStyle = '#9A8FB0'
    for (let i = 0; i < inputCount; i++) {
      ctx.save()
      ctx.translate(LABEL_W + i * CELL + CELL / 2, LABEL_H - 4)
      ctx.rotate(-Math.PI / 4)
      const label = inputLabels[i]?.currentLabel || `In ${i + 1}`
      ctx.fillText(label.slice(0, 8), 0, 0)
      ctx.restore()
    }
    ctx.restore()

    // Output labels (left)
    for (let o = 0; o < outputCount; o++) {
      const label = outputLabels[o]?.currentLabel || `Out ${o + 1}`
      ctx.fillStyle = '#9A8FB0'
      ctx.font = '10px Consolas, monospace'
      ctx.fillText(label.slice(0, 12), 4, LABEL_H + o * CELL + CELL / 2 + 3)
    }

    // Grid
    for (let o = 0; o < outputCount; o++) {
      for (let i = 0; i < inputCount; i++) {
        const x = LABEL_W + i * CELL
        const y = LABEL_H + o * CELL
        const isRouted = routeMap.get(o) === i

        ctx.strokeStyle = 'rgb(50, 45, 65)'
        ctx.strokeRect(x, y, CELL, CELL)

        if (isRouted) {
          const colorId = outputLabels[o]?.currentColor || 4
          const color = KUMO_COLORS[colorId]?.active || '#009af4'
          ctx.fillStyle = color
          ctx.fillRect(x + 2, y + 2, CELL - 4, CELL - 4)
        }
      }
    }
  }, [crosspoints, loading, inputCount, outputCount, inputLabels, outputLabels])

  const handleCanvasClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current
    if (!canvas) return
    const rect = canvas.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    const col = Math.floor((x - LABEL_W) / CELL)
    const row = Math.floor((y - LABEL_H) / CELL)

    if (col >= 0 && col < inputCount && row >= 0 && row < outputCount) {
      handleRoute(row, col)
    }
  }

  return (
    <DialogWrapper title="Crosspoint Matrix" onClose={closeDialog} width="max-w-4xl">
      <div className="space-y-3">
        {loading ? (
          <div className="text-center py-8 text-helix-text-muted">Loading crosspoints...</div>
        ) : (
          <div className="overflow-auto max-h-[600px] max-w-full">
            <canvas
              ref={canvasRef}
              onClick={handleCanvasClick}
              className="cursor-pointer"
              style={{ imageRendering: 'pixelated' }}
            />
          </div>
        )}
        <div className="flex justify-between items-center">
          <button onClick={loadCrosspoints} className="px-3 py-1.5 text-xs bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">
            Refresh
          </button>
          <div className="text-xs text-helix-text-muted">Click a cell to route input to output</div>
          <button onClick={closeDialog} className="px-4 py-2 text-sm bg-helix-surface border border-helix-border rounded hover:bg-helix-surface-hover text-helix-text">Close</button>
        </div>
      </div>
    </DialogWrapper>
  )
}
