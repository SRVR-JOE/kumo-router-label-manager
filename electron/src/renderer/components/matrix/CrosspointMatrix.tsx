import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react'
import { useRouterStore } from '../../stores/router-store'
import { useLabelsStore } from '../../stores/labels-store'
import { useUIStore } from '../../stores/ui-store'
import { KUMO_COLORS } from '../../theme/colors'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Crosspoint {
  output: number
  input: number
}

// ---------------------------------------------------------------------------
// Theme constants
// ---------------------------------------------------------------------------

const C = {
  bg:           '#1E1928',
  surface:      '#282337',
  surfaceHover: '#322D41',
  border:       '#463C5A',
  accent:       '#7B2FBE',
  accentHover:  '#9040DE',
  text:         '#E8E0F0',
  textMuted:    '#9A8FB0',
  textDim:      '#6B5F80',
} as Record<string, string>

// ---------------------------------------------------------------------------
// Memoised cell component
// ---------------------------------------------------------------------------

interface MatrixCellProps {
  outputIdx: number
  inputIdx: number
  isRouted: boolean
  color: string
  cellSize: number
  isHoveredRow: boolean
  isHoveredCol: boolean
  flashKey: string | null
  onRoute: (o: number, i: number) => void
  onClear: (o: number) => void
  onHover: (o: number, i: number) => void
  inputLabel: string
  outputLabel: string
}

const MatrixCell = React.memo(function MatrixCell({
  outputIdx,
  inputIdx,
  isRouted,
  color,
  cellSize,
  isHoveredRow,
  isHoveredCol,
  flashKey,
  onRoute,
  onClear,
  onHover,
  inputLabel,
  outputLabel,
}: MatrixCellProps) {
  const [flash, setFlash] = useState<'route' | 'clear' | null>(null)

  useEffect(() => {
    if (!flashKey) return
    const type = flashKey.startsWith('route') ? 'route' as const : 'clear' as const
    setFlash(type)
    const t = setTimeout(() => setFlash(null), 400)
    return () => clearTimeout(t)
  }, [flashKey])

  const handleClick = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    if (!isRouted) {
      onRoute(outputIdx, inputIdx)
    }
  }, [isRouted, onRoute, outputIdx, inputIdx])

  const handleContextMenu = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    if (isRouted) {
      onClear(outputIdx)
    }
  }, [isRouted, onClear, outputIdx])

  const handleMouseEnter = useCallback(() => {
    onHover(outputIdx, inputIdx)
  }, [onHover, outputIdx, inputIdx])

  const crosshair = isHoveredRow || isHoveredCol
  const isIntersection = isHoveredRow && isHoveredCol

  let bgColor = C.bg
  if (crosshair && !isRouted) {
    bgColor = isIntersection ? 'rgba(123, 47, 190, 0.18)' : 'rgba(123, 47, 190, 0.07)'
  }

  let borderColor = C.border
  if (isIntersection) {
    borderColor = C.accentHover
  } else if (crosshair) {
    borderColor = 'rgba(123, 47, 190, 0.35)'
  }

  let flashBg = ''
  if (flash === 'route') flashBg = 'rgba(96, 183, 31, 0.35)'
  if (flash === 'clear') flashBg = 'rgba(254, 0, 0, 0.2)'

  const tooltipText = `Input ${inputIdx + 1} → Output ${outputIdx + 1}\n${inputLabel} → ${outputLabel}`

  return (
    <div
      onClick={handleClick}
      onContextMenu={handleContextMenu}
      onMouseEnter={handleMouseEnter}
      title={tooltipText}
      style={{
        width: cellSize,
        height: cellSize,
        minWidth: cellSize,
        minHeight: cellSize,
        background: flashBg || bgColor,
        borderRight: `1px solid ${borderColor}`,
        borderBottom: `1px solid ${borderColor}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        cursor: isRouted ? 'default' : 'pointer',
        transition: 'background 150ms ease, border-color 150ms ease',
        position: 'relative',
      }}
    >
      {isRouted && (
        <div
          style={{
            width: cellSize - 8,
            height: cellSize - 8,
            borderRadius: 4,
            background: color,
            boxShadow: `0 0 6px ${color}66, inset 0 1px 2px rgba(0,0,0,0.35)`,
            transition: 'opacity 300ms ease, transform 300ms ease',
            opacity: flash === 'clear' ? 0.3 : 1,
            transform: flash === 'clear' ? 'scale(0.5)' : 'scale(1)',
          }}
        />
      )}
    </div>
  )
})

// ---------------------------------------------------------------------------
// Skeleton loader
// ---------------------------------------------------------------------------

function SkeletonGrid() {
  const rows = 8
  const cols = 8
  return (
    <div style={{ padding: 32, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <svg width="20" height="20" viewBox="0 0 20 20" style={{ animation: 'xpt-spin 1s linear infinite' }}>
          <circle cx="10" cy="10" r="8" fill="none" stroke={C.accent} strokeWidth="2.5"
            strokeDasharray="32" strokeDashoffset="8" strokeLinecap="round" />
        </svg>
        <span style={{ color: C.textMuted, fontSize: 13 }}>Loading crosspoints...</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 28px)`, gap: 2, opacity: 0.25 }}>
        {Array.from({ length: rows * cols }).map((_, i) => (
          <div key={i} style={{
            width: 28, height: 28,
            background: C.bg,
            borderRadius: 3,
            border: `1px solid ${C.border}`,
          }} />
        ))}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export default function CrosspointMatrix() {
  const { closeDialog, showToast } = useUIStore()
  const router = useRouterStore()
  const labels = useLabelsStore()

  const [crosspoints, setCrosspoints] = useState<Crosspoint[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [hoveredRow, setHoveredRow] = useState<number | null>(null)
  const [hoveredCol, setHoveredCol] = useState<number | null>(null)
  const [statusMsg, setStatusMsg] = useState<string>('')
  const [flashMap, setFlashMap] = useState<Record<string, string>>({})
  const scrollRef = useRef<HTMLDivElement>(null)

  const inputCount = router.inputCount
  const outputCount = router.outputCount
  const isKumo = router.routerType === 'kumo'

  const cellSize = (inputCount <= 32 && outputCount <= 32) ? 32 : 26

  const inputLabels = useMemo(() =>
    labels.labels
      .filter(l => l.portType === 'INPUT')
      .sort((a, b) => a.portNumber - b.portNumber),
    [labels.labels]
  )

  const outputLabels = useMemo(() =>
    labels.labels
      .filter(l => l.portType === 'OUTPUT')
      .sort((a, b) => a.portNumber - b.portNumber),
    [labels.labels]
  )

  // Build route map: output index -> input index
  const routeMap = useMemo(() => {
    const m = new Map<number, number>()
    for (const xpt of crosspoints) {
      m.set(xpt.output, xpt.input)
    }
    return m
  }, [crosspoints])

  const activeRouteCount = routeMap.size

  // ---- data loading -------------------------------------------------------

  const loadCrosspoints = useCallback(async (isRefresh = false) => {
    if (isRefresh) setRefreshing(true)
    else setLoading(true)

    try {
      const xpts = await window.helix.router.getCrosspoints() as Crosspoint[]
      setCrosspoints(xpts)
    } catch {
      showToast('Failed to load crosspoints', 'error')
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [showToast])

  useEffect(() => { loadCrosspoints() }, [loadCrosspoints])

  // ---- route actions ------------------------------------------------------

  const handleRoute = useCallback(async (output: number, input: number) => {
    const ok = await window.helix.router.setRoute(output, input) as boolean
    if (ok) {
      setCrosspoints(prev => {
        const filtered = prev.filter(x => x.output !== output)
        return [...filtered, { output, input }]
      })
      const inName = inputLabels[input]?.currentLabel || `Input ${input + 1}`
      const outName = outputLabels[output]?.currentLabel || `Output ${output + 1}`
      setStatusMsg(`Routed ${inName} → ${outName}`)
      showToast(`Route: Input ${input + 1} → Output ${output + 1}`, 'success')
      setFlashMap(prev => ({ ...prev, [`${output}-${input}`]: `route-${Date.now()}` }))
    } else {
      showToast('Route failed', 'error')
      setStatusMsg('Route failed')
    }
  }, [inputLabels, outputLabels, showToast])

  const handleClear = useCallback(async (output: number) => {
    // Route to input 0 to disconnect
    const currentInput = routeMap.get(output)
    if (currentInput === undefined) return

    setFlashMap(prev => ({ ...prev, [`${output}-${currentInput}`]: `clear-${Date.now()}` }))

    const ok = await window.helix.router.setRoute(output, 0) as boolean
    if (ok) {
      setCrosspoints(prev => {
        const filtered = prev.filter(x => x.output !== output)
        // Route to input 0
        return [...filtered, { output, input: 0 }]
      })
      const outName = outputLabels[output]?.currentLabel || `Output ${output + 1}`
      setStatusMsg(`Cleared ${outName}`)
      showToast(`Cleared Output ${output + 1}`, 'info')
    } else {
      showToast('Clear failed', 'error')
    }
  }, [routeMap, outputLabels, showToast])

  const handleCellHover = useCallback((row: number, col: number) => {
    setHoveredRow(row)
    setHoveredCol(col)
  }, [])

  const handleMouseLeave = useCallback(() => {
    setHoveredRow(null)
    setHoveredCol(null)
  }, [])

  // ---- color helper -------------------------------------------------------

  const getRouteColor = useCallback((outputIdx: number): string => {
    if (isKumo) {
      const colorId = outputLabels[outputIdx]?.currentColor || 4
      return KUMO_COLORS[colorId]?.active || KUMO_COLORS[4].active
    }
    return C.accent
  }, [isKumo, outputLabels])

  // ---- keyboard -----------------------------------------------------------

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeDialog()
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [closeDialog])

  // ---- render helpers -----------------------------------------------------

  const routerTypeBadge = router.routerType ? router.routerType.toUpperCase() : 'ROUTER'
  const portLabel = `${inputCount} x ${outputCount}`
  const LABEL_COL_W = 160
  const LABEL_ROW_H = 140

  // ---- render -------------------------------------------------------------

  return (
    <>
      {/* Inject keyframes */}
      <style>{`
        @keyframes xpt-spin { to { transform: rotate(360deg); } }
        @keyframes xpt-flash-in {
          0% { background: rgba(96,183,31,0.45); }
          100% { background: transparent; }
        }
        @keyframes xpt-fadein {
          from { opacity: 0; transform: scale(0.97); }
          to { opacity: 1; transform: scale(1); }
        }
      `}</style>

      {/* Full-screen overlay */}
      <div
        style={{
          position: 'fixed',
          inset: 0,
          zIndex: 9999,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'rgba(0, 0, 0, 0.65)',
          backdropFilter: 'blur(4px)',
          animation: 'xpt-fadein 200ms ease-out',
        }}
        onClick={(e) => { if (e.target === e.currentTarget) closeDialog() }}
      >
        {/* Content panel */}
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            maxWidth: '95vw',
            maxHeight: '95vh',
            width: 'fit-content',
            background: C.surface,
            borderRadius: 12,
            border: `1px solid ${C.border}`,
            boxShadow: '0 24px 80px rgba(0,0,0,0.5)',
            overflow: 'hidden',
          }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* ---- TOOLBAR ---- */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '12px 20px',
              borderBottom: `1px solid ${C.border}`,
              background: C.surface,
              flexShrink: 0,
            }}
          >
            {/* Left: title + badges */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              {/* Grid icon */}
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
                <rect x="2" y="2" width="6" height="6" rx="1" fill={C.accent} />
                <rect x="10" y="2" width="6" height="6" rx="1" fill={C.accent} opacity="0.5" />
                <rect x="2" y="10" width="6" height="6" rx="1" fill={C.accent} opacity="0.5" />
                <rect x="10" y="10" width="6" height="6" rx="1" fill={C.accent} />
              </svg>
              <span style={{ color: C.text, fontWeight: 600, fontSize: 15 }}>
                Crosspoint Matrix
              </span>
              {router.deviceName && (
                <span style={{ color: C.textMuted, fontSize: 13 }}>
                  {router.deviceName}
                </span>
              )}
              {/* Router type badge */}
              <span style={{
                background: C.accent + '22',
                color: C.accent,
                fontSize: 10,
                fontWeight: 700,
                padding: '2px 8px',
                borderRadius: 4,
                letterSpacing: 0.5,
                textTransform: 'uppercase',
              }}>
                {routerTypeBadge}
              </span>
              {/* Port count */}
              <span style={{
                background: C.border + '55',
                color: C.textMuted,
                fontSize: 11,
                fontWeight: 600,
                padding: '2px 8px',
                borderRadius: 4,
              }}>
                {portLabel}
              </span>
            </div>

            {/* Right: refresh + close */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {/* Refresh button */}
              <button
                onClick={() => loadCrosspoints(true)}
                disabled={refreshing}
                title="Refresh crosspoints"
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: 32,
                  height: 32,
                  border: `1px solid ${C.border}`,
                  borderRadius: 6,
                  background: C.bg,
                  color: C.textMuted,
                  cursor: refreshing ? 'wait' : 'pointer',
                  transition: 'background 150ms, border-color 150ms',
                }}
                onMouseEnter={e => {
                  e.currentTarget.style.background = C.surfaceHover
                  e.currentTarget.style.borderColor = C.accentHover
                }}
                onMouseLeave={e => {
                  e.currentTarget.style.background = C.bg
                  e.currentTarget.style.borderColor = C.border
                }}
              >
                <svg
                  width="14" height="14" viewBox="0 0 16 16" fill="none"
                  style={{
                    animation: refreshing ? 'xpt-spin 0.8s linear infinite' : 'none',
                    transition: 'transform 200ms',
                  }}
                >
                  <path
                    d="M14 8a6 6 0 11-1.5-3.94"
                    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"
                  />
                  <path d="M14 2v4h-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>

              {/* Close button */}
              <button
                onClick={closeDialog}
                title="Close (Esc)"
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: 32,
                  height: 32,
                  border: `1px solid ${C.border}`,
                  borderRadius: 6,
                  background: C.bg,
                  color: C.textMuted,
                  cursor: 'pointer',
                  transition: 'background 150ms, border-color 150ms, color 150ms',
                }}
                onMouseEnter={e => {
                  e.currentTarget.style.background = '#3d1520'
                  e.currentTarget.style.borderColor = '#aa3344'
                  e.currentTarget.style.color = '#ff6677'
                }}
                onMouseLeave={e => {
                  e.currentTarget.style.background = C.bg
                  e.currentTarget.style.borderColor = C.border
                  e.currentTarget.style.color = C.textMuted
                }}
              >
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M2 2l10 10M12 2L2 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                </svg>
              </button>
            </div>
          </div>

          {/* ---- MATRIX BODY ---- */}
          {loading ? (
            <SkeletonGrid />
          ) : (
            <div
              ref={scrollRef}
              onMouseLeave={handleMouseLeave}
              style={{
                overflow: 'auto',
                flex: 1,
                minHeight: 0,
                position: 'relative',
              }}
            >
              {/* CSS Grid matrix wrapper */}
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: `${LABEL_COL_W}px repeat(${inputCount}, ${cellSize}px)`,
                  gridTemplateRows: `${LABEL_ROW_H}px repeat(${outputCount}, ${cellSize}px)`,
                  width: 'fit-content',
                  minWidth: '100%',
                }}
              >
                {/* ---- TOP-LEFT CORNER (empty) ---- */}
                <div
                  style={{
                    position: 'sticky',
                    top: 0,
                    left: 0,
                    zIndex: 30,
                    background: C.surface,
                    borderRight: `1px solid ${C.border}`,
                    borderBottom: `2px solid ${C.border}`,
                    display: 'flex',
                    alignItems: 'flex-end',
                    justifyContent: 'flex-end',
                    padding: '4px 8px',
                  }}
                >
                  <span style={{ color: C.textDim, fontSize: 9, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
                    OUT / IN
                  </span>
                </div>

                {/* ---- INPUT LABELS (top header row) ---- */}
                {Array.from({ length: inputCount }).map((_, i) => {
                  const label = inputLabels[i]?.currentLabel || `In ${i + 1}`
                  const highlighted = hoveredCol === i
                  return (
                    <div
                      key={`ih-${i}`}
                      style={{
                        position: 'sticky',
                        top: 0,
                        zIndex: 20,
                        background: highlighted
                          ? `linear-gradient(180deg, ${C.surface} 0%, rgba(123,47,190,0.1) 100%)`
                          : C.surface,
                        borderRight: `1px solid ${C.border}`,
                        borderBottom: `2px solid ${highlighted ? C.accent : C.border}`,
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        justifyContent: 'flex-start',
                        padding: '6px 0 6px 0',
                        overflow: 'hidden',
                        transition: 'background 150ms, border-color 150ms',
                      }}
                      title={label}
                    >
                      {/* Port number */}
                      <span
                        style={{
                          fontSize: 15,
                          fontWeight: 800,
                          color: highlighted ? C.text : C.accent,
                          fontFamily: 'Consolas, "Courier New", monospace',
                          lineHeight: 1,
                          marginBottom: 3,
                          flexShrink: 0,
                        }}
                      >
                        {i + 1}
                      </span>
                      {/* Label name - vertical, reading top to bottom */}
                      <div
                        style={{
                          writingMode: 'vertical-lr',
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          maxHeight: LABEL_ROW_H - 26,
                          fontSize: 16,
                          fontFamily: 'Consolas, "Courier New", monospace',
                          fontWeight: highlighted ? 700 : 500,
                          color: highlighted ? C.text : C.textMuted,
                          transition: 'color 150ms',
                          lineHeight: 1.1,
                        }}
                      >
                        {label}
                      </div>
                    </div>
                  )
                })}

                {/* ---- OUTPUT ROWS ---- */}
                {Array.from({ length: outputCount }).map((_, o) => {
                  const outLabel = outputLabels[o]?.currentLabel || `Out ${o + 1}`
                  const rowHighlighted = hoveredRow === o
                  const routeColor = getRouteColor(o)

                  return (
                    <React.Fragment key={`row-${o}`}>
                      {/* Output label (sticky left) */}
                      <div
                        style={{
                          position: 'sticky',
                          left: 0,
                          zIndex: 10,
                          background: rowHighlighted
                            ? `linear-gradient(90deg, ${C.surface} 0%, rgba(123,47,190,0.1) 100%)`
                            : C.surface,
                          borderRight: `2px solid ${rowHighlighted ? C.accent : C.border}`,
                          borderBottom: `1px solid ${C.border}`,
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'flex-end',
                          paddingRight: 10,
                          paddingLeft: 6,
                          height: cellSize,
                          overflow: 'hidden',
                          transition: 'background 150ms, border-color 150ms',
                        }}
                        title={outLabel}
                      >
                        {/* Color dot for KUMO */}
                        {isKumo && (
                          <div style={{
                            width: 6,
                            height: 6,
                            borderRadius: 3,
                            background: routeColor,
                            marginRight: 6,
                            flexShrink: 0,
                          }} />
                        )}
                        {/* Port number */}
                        <span
                          style={{
                            fontSize: 15,
                            fontWeight: 800,
                            color: rowHighlighted ? C.text : C.accent,
                            fontFamily: 'Consolas, "Courier New", monospace',
                            marginRight: 8,
                            flexShrink: 0,
                            minWidth: 26,
                            textAlign: 'right',
                          }}
                        >
                          {o + 1}
                        </span>
                        <span
                          style={{
                            fontSize: 16,
                            fontFamily: 'Consolas, "Courier New", monospace',
                            fontWeight: rowHighlighted ? 700 : 500,
                            color: rowHighlighted ? C.text : C.textMuted,
                            whiteSpace: 'nowrap',
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            maxWidth: LABEL_COL_W - 50,
                            textAlign: 'right',
                            transition: 'color 150ms',
                          }}
                        >
                          {outLabel}
                        </span>
                      </div>

                      {/* Cells for this row */}
                      {Array.from({ length: inputCount }).map((_, i) => {
                        const isRouted = routeMap.get(o) === i
                        const cellKey = `${o}-${i}`
                        return (
                          <MatrixCell
                            key={cellKey}
                            outputIdx={o}
                            inputIdx={i}
                            isRouted={isRouted}
                            color={routeColor}
                            cellSize={cellSize}
                            isHoveredRow={hoveredRow === o}
                            isHoveredCol={hoveredCol === i}
                            flashKey={flashMap[cellKey] || null}
                            onRoute={handleRoute}
                            onClear={handleClear}
                            onHover={handleCellHover}
                            inputLabel={inputLabels[i]?.currentLabel || `Input ${i + 1}`}
                            outputLabel={outLabel}
                          />
                        )
                      })}
                    </React.Fragment>
                  )
                })}
              </div>
            </div>
          )}

          {/* ---- STATUS BAR ---- */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '8px 20px',
              borderTop: `1px solid ${C.border}`,
              background: C.surface,
              flexShrink: 0,
              minHeight: 36,
            }}
          >
            {/* Left: route count */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <div style={{
                width: 8,
                height: 8,
                borderRadius: 4,
                background: activeRouteCount > 0 ? '#60b71f' : C.textDim,
                boxShadow: activeRouteCount > 0 ? '0 0 6px #60b71f66' : 'none',
              }} />
              <span style={{ color: C.textMuted, fontSize: 11, fontWeight: 500 }}>
                {activeRouteCount} route{activeRouteCount !== 1 ? 's' : ''} active
              </span>
            </div>

            {/* Center: last action */}
            <span style={{
              color: C.textDim,
              fontSize: 11,
              fontStyle: statusMsg ? 'normal' : 'italic',
              transition: 'color 300ms',
            }}>
              {statusMsg || '\u2014'}
            </span>

            {/* Right: instructions */}
            <span style={{ color: C.textDim, fontSize: 10 }}>
              Click to route
              <span style={{ margin: '0 6px', color: C.border }}>|</span>
              Right-click to clear
            </span>
          </div>
        </div>
      </div>
    </>
  )
}
