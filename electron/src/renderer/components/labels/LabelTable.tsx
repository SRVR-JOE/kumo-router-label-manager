import React, { useState, useCallback, useRef, useEffect, useMemo } from 'react'
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  flexRender,
  createColumnHelper,
  SortingState,
} from '@tanstack/react-table'
import { useLabelsStore, LabelRow } from '../../stores/labels-store'
import { KUMO_COLORS } from '../../theme/colors'

const columnHelper = createColumnHelper<LabelRow>()

// Columns that support drag-select bulk editing
const EDITABLE_FIELDS: Record<string, keyof LabelRow> = {
  newLabel: 'newLabel',
  newLabelLine2: 'newLabelLine2',
  newColor: 'newColor',
  notes: 'notes',
}

interface SelectionRange {
  colId: string
  startRowIdx: number
  endRowIdx: number
}

function EditableCell({ value, onChange, className = '', isSelected, onCellMouseDown, onCellMouseEnter }: {
  value: string
  onChange: (v: string) => void
  className?: string
  isSelected?: boolean
  onCellMouseDown?: (e: React.MouseEvent) => void
  onCellMouseEnter?: (e: React.MouseEvent) => void
}) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { setDraft(value) }, [value])
  useEffect(() => { if (editing) inputRef.current?.focus() }, [editing])

  if (editing) {
    return (
      <input
        ref={inputRef}
        className="cell-edit"
        value={draft}
        onChange={e => setDraft(e.target.value)}
        onBlur={() => { setEditing(false); if (draft !== value) onChange(draft) }}
        onKeyDown={e => {
          if (e.key === 'Enter') { setEditing(false); if (draft !== value) onChange(draft) }
          if (e.key === 'Escape') { setEditing(false); setDraft(value) }
        }}
      />
    )
  }
  return (
    <div
      className={`cursor-text truncate px-1 min-h-[22px] ${className} ${isSelected ? 'cell-selected' : ''}`}
      onDoubleClick={() => setEditing(true)}
      onMouseDown={onCellMouseDown}
      onMouseEnter={onCellMouseEnter}
      title={value}
    >
      {value || '\u00A0'}
    </div>
  )
}

function ColorCell({ color, isActive }: { color: number; isActive?: boolean }) {
  const c = KUMO_COLORS[color]
  if (!c) return <span>{color}</span>
  return (
    <div className="flex items-center gap-1">
      <span className="color-badge" style={{ backgroundColor: isActive ? c.active : c.idle }} />
      <span className="text-xs">{c.name}</span>
    </div>
  )
}

function ColorDropdown({ value, onChange, isSelected, onCellMouseDown, onCellMouseEnter }: {
  value: number | null
  onChange: (v: number | null) => void
  isSelected?: boolean
  onCellMouseDown?: (e: React.MouseEvent) => void
  onCellMouseEnter?: (e: React.MouseEvent) => void
}) {
  return (
    <div
      className={isSelected ? 'cell-selected' : ''}
      onMouseDown={onCellMouseDown}
      onMouseEnter={onCellMouseEnter}
    >
      <select
        className="bg-transparent border border-helix-border rounded text-xs px-1 py-0.5 text-helix-text w-full"
        value={value ?? ''}
        onChange={e => onChange(e.target.value ? parseInt(e.target.value, 10) : null)}
      >
        <option value="">—</option>
        {Object.entries(KUMO_COLORS).map(([id, c]) => (
          <option key={id} value={id}>{c.name}</option>
        ))}
      </select>
    </div>
  )
}

function BulkEditPopup({ selection, rowIds, field, onApply, onCancel, anchorRect }: {
  selection: SelectionRange
  rowIds: string[]
  field: string
  onApply: (value: string) => void
  onCancel: () => void
  anchorRect: { top: number; left: number } | null
}) {
  const [value, setValue] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)
  const isColor = field === 'newColor'

  useEffect(() => { inputRef.current?.focus() }, [])

  const count = Math.abs(selection.endRowIdx - selection.startRowIdx) + 1

  return (
    <div
      className="fixed z-50 bg-helix-surface border border-helix-accent rounded shadow-lg p-3 flex flex-col gap-2"
      style={{
        top: anchorRect ? anchorRect.top : '50%',
        left: anchorRect ? anchorRect.left + 10 : '50%',
      }}
    >
      <div className="text-xs text-helix-text-muted">
        Bulk edit {count} cells in <span className="text-helix-accent font-medium">{field}</span>
      </div>
      {isColor ? (
        <select
          ref={inputRef as unknown as React.Ref<HTMLSelectElement>}
          className="bg-helix-bg border border-helix-border rounded text-xs px-2 py-1 text-helix-text"
          value={value}
          onChange={e => setValue(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter') onApply(value)
            if (e.key === 'Escape') onCancel()
          }}
        >
          <option value="">— Clear —</option>
          {Object.entries(KUMO_COLORS).map(([id, c]) => (
            <option key={id} value={id}>{c.name}</option>
          ))}
        </select>
      ) : (
        <input
          ref={inputRef}
          className="bg-helix-bg border border-helix-border rounded text-xs px-2 py-1 text-helix-text w-48"
          placeholder="Enter value for all selected cells..."
          value={value}
          onChange={e => setValue(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Enter') onApply(value)
            if (e.key === 'Escape') onCancel()
          }}
        />
      )}
      <div className="flex gap-2">
        <button
          className="px-3 py-1 text-xs bg-helix-accent text-white rounded hover:bg-helix-accent-hover"
          onClick={() => onApply(value)}
        >
          Apply
        </button>
        <button
          className="px-3 py-1 text-xs bg-helix-bg text-helix-text-muted border border-helix-border rounded hover:text-helix-text"
          onClick={onCancel}
        >
          Cancel
        </button>
      </div>
    </div>
  )
}

export default function LabelTable() {
  const { labels, filter, searchText, setFilter, setSearchText, updateLabel, bulkUpdateLabels, getFilteredLabels } = useLabelsStore()
  const [sorting, setSorting] = useState<SortingState>([])

  // Selection state
  const [selection, setSelection] = useState<SelectionRange | null>(null)
  const [isDragging, setIsDragging] = useState(false)
  const [showBulkEdit, setShowBulkEdit] = useState(false)
  const [bulkEditAnchor, setBulkEditAnchor] = useState<{ top: number; left: number } | null>(null)
  const tableRef = useRef<HTMLDivElement>(null)

  const filteredLabels = useMemo(() => getFilteredLabels(), [labels, filter, searchText])

  // Get selected row indices (normalized min/max)
  const getSelectionRows = useCallback((sel: SelectionRange) => {
    const min = Math.min(sel.startRowIdx, sel.endRowIdx)
    const max = Math.max(sel.startRowIdx, sel.endRowIdx)
    return { min, max }
  }, [])

  // Check if a cell is in the current selection
  const isCellSelected = useCallback((rowIdx: number, colId: string): boolean => {
    if (!selection) return false
    if (selection.colId !== colId) return false
    const { min, max } = getSelectionRows(selection)
    return rowIdx >= min && rowIdx <= max
  }, [selection, getSelectionRows])

  // Mouse handlers for drag selection
  const handleCellMouseDown = useCallback((rowIdx: number, colId: string, e: React.MouseEvent) => {
    if (!(colId in EDITABLE_FIELDS)) return
    // Don't start drag if clicking on an input/select
    if ((e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).tagName === 'SELECT') return

    e.preventDefault()
    setShowBulkEdit(false)
    setSelection({ colId, startRowIdx: rowIdx, endRowIdx: rowIdx })
    setIsDragging(true)
  }, [])

  const handleCellMouseEnter = useCallback((rowIdx: number, colId: string) => {
    if (!isDragging || !selection) return
    if (colId !== selection.colId) return
    setSelection(prev => prev ? { ...prev, endRowIdx: rowIdx } : null)
  }, [isDragging, selection])

  // Global mouseup to end dragging
  useEffect(() => {
    const handleMouseUp = () => {
      if (isDragging && selection) {
        setIsDragging(false)
        const { min, max } = getSelectionRows(selection)
        if (min !== max || true) {
          // Show bulk edit popup - position near last mouse position
          setBulkEditAnchor({ top: Math.min(window.innerHeight - 150, max * 28 + 100), left: 300 })
          setShowBulkEdit(true)
        }
      }
    }
    window.addEventListener('mouseup', handleMouseUp)
    return () => window.removeEventListener('mouseup', handleMouseUp)
  }, [isDragging, selection, getSelectionRows])

  // Escape to cancel selection
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setSelection(null)
        setShowBulkEdit(false)
        setIsDragging(false)
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  const handleBulkApply = useCallback((value: string) => {
    if (!selection) return
    const { min, max } = getSelectionRows(selection)
    const field = EDITABLE_FIELDS[selection.colId]
    if (!field) return

    const selectedIds = filteredLabels.slice(min, max + 1).map(l => l.id)

    if (field === 'newColor') {
      bulkUpdateLabels(selectedIds, field, value ? parseInt(value, 10) : null)
    } else {
      bulkUpdateLabels(selectedIds, field, value)
    }

    setSelection(null)
    setShowBulkEdit(false)
  }, [selection, filteredLabels, bulkUpdateLabels, getSelectionRows])

  const handleBulkCancel = useCallback(() => {
    setSelection(null)
    setShowBulkEdit(false)
  }, [])

  const columns = useMemo(() => [
    columnHelper.accessor('portNumber', {
      header: 'Port#',
      size: 55,
      cell: info => <span className="text-center block">{info.getValue()}</span>,
    }),
    columnHelper.accessor('portType', {
      header: 'Type',
      size: 65,
      cell: info => (
        <span className={`text-xs font-medium ${info.getValue() === 'INPUT' ? 'text-blue-400' : 'text-orange-400'}`}>
          {info.getValue()}
        </span>
      ),
    }),
    columnHelper.accessor('currentLabel', {
      header: 'Current Label',
      size: 150,
      cell: info => <span className="truncate block" title={info.getValue()}>{info.getValue()}</span>,
    }),
    columnHelper.accessor('currentLabelLine2', {
      header: 'Current L2',
      size: 120,
      cell: info => <span className="truncate block text-helix-text-muted" title={info.getValue()}>{info.getValue()}</span>,
    }),
    columnHelper.accessor('newLabel', {
      header: 'New Label',
      size: 150,
      cell: info => (
        <EditableCell
          value={info.getValue()}
          onChange={v => updateLabel(info.row.original.id, 'newLabel', v)}
          className={info.getValue() && info.getValue() !== info.row.original.currentLabel ? 'text-helix-accent font-medium' : ''}
          isSelected={isCellSelected(info.row.index, 'newLabel')}
          onCellMouseDown={e => handleCellMouseDown(info.row.index, 'newLabel', e)}
          onCellMouseEnter={e => handleCellMouseEnter(info.row.index, 'newLabel')}
        />
      ),
    }),
    columnHelper.accessor('newLabelLine2', {
      header: 'New L2',
      size: 120,
      cell: info => (
        <EditableCell
          value={info.getValue()}
          onChange={v => updateLabel(info.row.original.id, 'newLabelLine2', v)}
          isSelected={isCellSelected(info.row.index, 'newLabelLine2')}
          onCellMouseDown={e => handleCellMouseDown(info.row.index, 'newLabelLine2', e)}
          onCellMouseEnter={e => handleCellMouseEnter(info.row.index, 'newLabelLine2')}
        />
      ),
    }),
    columnHelper.accessor('currentColor', {
      header: 'Color',
      size: 100,
      cell: info => <ColorCell color={info.getValue()} />,
    }),
    columnHelper.accessor('newColor', {
      header: 'New Color',
      size: 100,
      cell: info => (
        <ColorDropdown
          value={info.getValue()}
          onChange={v => updateLabel(info.row.original.id, 'newColor', v)}
          isSelected={isCellSelected(info.row.index, 'newColor')}
          onCellMouseDown={e => handleCellMouseDown(info.row.index, 'newColor', e)}
          onCellMouseEnter={e => handleCellMouseEnter(info.row.index, 'newColor')}
        />
      ),
    }),
    columnHelper.accessor('notes', {
      header: 'Notes',
      size: 120,
      cell: info => (
        <EditableCell
          value={info.getValue()}
          onChange={v => updateLabel(info.row.original.id, 'notes', v)}
          isSelected={isCellSelected(info.row.index, 'notes')}
          onCellMouseDown={e => handleCellMouseDown(info.row.index, 'notes', e)}
          onCellMouseEnter={e => handleCellMouseEnter(info.row.index, 'notes')}
        />
      ),
    }),
    columnHelper.accessor('status', {
      header: 'Status',
      size: 70,
      cell: info => {
        const s = info.getValue()
        const colors = { unchanged: 'text-helix-text-dim', modified: 'text-yellow-400', uploaded: 'text-green-400', error: 'text-red-400' }
        const icons = { unchanged: '—', modified: '*', uploaded: '\u2713', error: '\u2717' }
        return <span className={`text-xs ${colors[s]}`}>{icons[s]}</span>
      },
    }),
  ], [updateLabel, isCellSelected, handleCellMouseDown, handleCellMouseEnter])

  const table = useReactTable({
    data: filteredLabels,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  return (
    <div className="flex flex-col flex-1 overflow-hidden" ref={tableRef}>
      {/* Toolbar */}
      <div className="flex items-center gap-2 px-3 py-2 bg-helix-surface border-b border-helix-border">
        {/* Filter tabs */}
        {(['all', 'inputs', 'outputs', 'changed'] as const).map(f => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-3 py-1 text-xs rounded ${filter === f ? 'bg-helix-accent text-white' : 'bg-helix-bg text-helix-text-muted hover:text-helix-text'}`}
          >
            {f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
        <div className="flex-1" />
        {selection && (
          <span className="text-xs text-helix-accent">
            {Math.abs(selection.endRowIdx - selection.startRowIdx) + 1} cells selected
          </span>
        )}
        {/* Search */}
        <input
          type="text"
          placeholder="Search..."
          value={searchText}
          onChange={e => setSearchText(e.target.value)}
          className="bg-helix-bg border border-helix-border rounded px-2 py-1 text-xs text-helix-text w-48 focus:border-helix-accent focus:outline-none"
        />
        <span className="text-xs text-helix-text-muted">{filteredLabels.length} rows</span>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto select-none">
        <table className="w-full text-sm border-collapse">
          <thead className="sticky top-0 z-10 bg-helix-surface">
            {table.getHeaderGroups().map(hg => (
              <tr key={hg.id}>
                {hg.headers.map(header => (
                  <th
                    key={header.id}
                    className="text-left px-2 py-1.5 text-xs font-semibold text-helix-text-muted border-b border-helix-border cursor-pointer select-none"
                    style={{ width: header.getSize() }}
                    onClick={header.column.getToggleSortingHandler()}
                  >
                    {flexRender(header.column.columnDef.header, header.getContext())}
                    {{ asc: ' \u25B2', desc: ' \u25BC' }[header.column.getIsSorted() as string] ?? ''}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map(row => (
              <tr
                key={row.id}
                className={`border-b border-helix-border/30 hover:bg-helix-surface-hover ${
                  row.original.status === 'modified' ? 'bg-yellow-900/10' :
                  row.original.status === 'uploaded' ? 'bg-green-900/10' :
                  row.original.status === 'error' ? 'bg-red-900/10' : ''
                }`}
              >
                {row.getVisibleCells().map(cell => (
                  <td key={cell.id} className="px-2 py-1" style={{ width: cell.column.getSize() }}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
            {filteredLabels.length === 0 && (
              <tr>
                <td colSpan={columns.length} className="text-center py-12 text-helix-text-dim">
                  {labels.length === 0 ? 'No labels loaded. Connect to a router or open a file.' : 'No matching labels.'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Bulk edit popup */}
      {showBulkEdit && selection && (
        <BulkEditPopup
          selection={selection}
          rowIds={[]}
          field={selection.colId}
          onApply={handleBulkApply}
          onCancel={handleBulkCancel}
          anchorRect={bulkEditAnchor}
        />
      )}
    </div>
  )
}
