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

function EditableCell({ value, onChange, className = '' }: { value: string; onChange: (v: string) => void; className?: string }) {
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
      className={`cursor-text truncate px-1 min-h-[22px] ${className}`}
      onDoubleClick={() => setEditing(true)}
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

function ColorDropdown({ value, onChange }: { value: number | null; onChange: (v: number | null) => void }) {
  return (
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
  )
}

export default function LabelTable() {
  const { labels, filter, searchText, setFilter, setSearchText, updateLabel, getFilteredLabels } = useLabelsStore()
  const [sorting, setSorting] = useState<SortingState>([])

  const filteredLabels = useMemo(() => getFilteredLabels(), [labels, filter, searchText])

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
  ], [updateLabel])

  const table = useReactTable({
    data: filteredLabels,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  return (
    <div className="flex flex-col flex-1 overflow-hidden">
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
      <div className="flex-1 overflow-auto">
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
    </div>
  )
}
