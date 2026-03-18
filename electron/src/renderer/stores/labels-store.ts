import { create } from 'zustand'

export interface LabelRow {
  id: string // "INPUT-1", "OUTPUT-3", etc.
  portNumber: number
  portType: 'INPUT' | 'OUTPUT'
  currentLabel: string
  newLabel: string
  currentLabelLine2: string
  newLabelLine2: string
  currentColor: number
  newColor: number | null
  notes: string
  status: 'unchanged' | 'modified' | 'uploaded' | 'error'
}

interface UndoEntry {
  labels: LabelRow[]
}

interface LabelsState {
  labels: LabelRow[]
  filter: 'all' | 'inputs' | 'outputs' | 'changed'
  searchText: string
  currentFilePath: string | null
  isDirty: boolean
  undoStack: UndoEntry[]
  redoStack: UndoEntry[]

  setLabels: (labels: LabelRow[]) => void
  updateLabel: (id: string, field: keyof LabelRow, value: string | number | null) => void
  setFilter: (filter: 'all' | 'inputs' | 'outputs' | 'changed') => void
  setSearchText: (text: string) => void
  setFilePath: (path: string | null) => void
  clearNewLabels: () => void
  copyCurrentToNew: () => void
  applyPrefix: (prefix: string, field: 'newLabel' | 'newLabelLine2') => void
  applySuffix: (suffix: string, field: 'newLabel' | 'newLabelLine2') => void
  autoNumber: (startPort: number, endPort: number, portType: 'INPUT' | 'OUTPUT' | 'ALL', prefix: string, startNum: number, padding: number) => void
  bulkUpdateLabels: (ids: string[], field: keyof LabelRow, value: string | number | null) => void
  findReplace: (find: string, replace: string, field: 'newLabel' | 'newLabelLine2', caseSensitive: boolean) => number
  markUploaded: (ids: string[]) => void
  undo: () => void
  redo: () => void

  getFilteredLabels: () => LabelRow[]
  getChangedLabels: () => LabelRow[]
}

function computeStatus(row: LabelRow): LabelRow['status'] {
  if (row.status === 'uploaded' || row.status === 'error') return row.status
  const labelChanged = row.newLabel !== '' && row.newLabel !== row.currentLabel
  const line2Changed = row.newLabelLine2 !== '' && row.newLabelLine2 !== row.currentLabelLine2
  const colorChanged = row.newColor !== null && row.newColor !== row.currentColor
  return (labelChanged || line2Changed || colorChanged) ? 'modified' : 'unchanged'
}

export const useLabelsStore = create<LabelsState>((set, get) => ({
  labels: [],
  filter: 'all',
  searchText: '',
  currentFilePath: null,
  isDirty: false,
  undoStack: [],
  redoStack: [],

  setLabels: (labels) => set({
    labels: labels.map(l => ({ ...l, status: computeStatus(l) })),
    isDirty: false,
    undoStack: [],
    redoStack: [],
  }),

  updateLabel: (id, field, value) => {
    const state = get()
    const prev = [...state.labels]
    const labels = state.labels.map(l => {
      if (l.id !== id) return l
      const updated = { ...l, [field]: value }
      updated.status = computeStatus(updated)
      return updated
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  setFilter: (filter) => set({ filter }),
  setSearchText: (text) => set({ searchText: text }),
  setFilePath: (path) => set({ currentFilePath: path }),

  clearNewLabels: () => {
    const state = get()
    const prev = [...state.labels]
    const labels = state.labels.map(l => ({
      ...l,
      newLabel: '',
      newLabelLine2: '',
      newColor: null,
      status: 'unchanged' as const,
    }))
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  copyCurrentToNew: () => {
    const state = get()
    const prev = [...state.labels]
    const labels = state.labels.map(l => ({
      ...l,
      newLabel: l.currentLabel,
      newLabelLine2: l.currentLabelLine2,
      status: 'unchanged' as const,
    }))
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  applyPrefix: (prefix, field) => {
    const state = get()
    const prev = [...state.labels]
    const labels = state.labels.map(l => {
      const val = l[field] || l.currentLabel
      const updated = { ...l, [field]: prefix + val }
      updated.status = computeStatus(updated)
      return updated
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  applySuffix: (suffix, field) => {
    const state = get()
    const prev = [...state.labels]
    const labels = state.labels.map(l => {
      const val = l[field] || l.currentLabel
      const updated = { ...l, [field]: val + suffix }
      updated.status = computeStatus(updated)
      return updated
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  autoNumber: (startPort, endPort, portType, prefix, startNum, padding) => {
    const state = get()
    const prev = [...state.labels]
    let counter = startNum
    const labels = state.labels.map(l => {
      if (l.portNumber < startPort || l.portNumber > endPort) return l
      if (portType !== 'ALL' && l.portType !== portType) return l
      const numStr = String(counter).padStart(padding, '0')
      counter++
      const updated = { ...l, newLabel: `${prefix}${numStr}` }
      updated.status = computeStatus(updated)
      return updated
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  bulkUpdateLabels: (ids, field, value) => {
    const state = get()
    const prev = [...state.labels]
    const idSet = new Set(ids)
    const labels = state.labels.map(l => {
      if (!idSet.has(l.id)) return l
      const updated = { ...l, [field]: value }
      updated.status = computeStatus(updated)
      return updated
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
  },

  findReplace: (find, replace, field, caseSensitive) => {
    const state = get()
    const prev = [...state.labels]
    let count = 0
    const flags = caseSensitive ? 'g' : 'gi'
    const regex = new RegExp(find.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags)
    const labels = state.labels.map(l => {
      const val = l[field] || l.currentLabel
      if (regex.test(val)) {
        const newVal = val.replace(regex, replace)
        count++
        regex.lastIndex = 0 // reset for next test
        const updated = { ...l, [field]: newVal }
        updated.status = computeStatus(updated)
        return updated
      }
      return l
    })
    set({
      labels,
      isDirty: true,
      undoStack: [...state.undoStack, { labels: prev }],
      redoStack: [],
    })
    return count
  },

  markUploaded: (ids) => {
    const idSet = new Set(ids)
    const labels = get().labels.map(l => {
      if (!idSet.has(l.id)) return l
      return {
        ...l,
        currentLabel: l.newLabel || l.currentLabel,
        currentLabelLine2: l.newLabelLine2 || l.currentLabelLine2,
        currentColor: l.newColor ?? l.currentColor,
        newLabel: '',
        newLabelLine2: '',
        newColor: null,
        status: 'uploaded' as const,
      }
    })
    set({ labels })
  },

  undo: () => {
    const state = get()
    if (state.undoStack.length === 0) return
    const entry = state.undoStack[state.undoStack.length - 1]
    set({
      labels: entry.labels,
      undoStack: state.undoStack.slice(0, -1),
      redoStack: [...state.redoStack, { labels: state.labels }],
    })
  },

  redo: () => {
    const state = get()
    if (state.redoStack.length === 0) return
    const entry = state.redoStack[state.redoStack.length - 1]
    set({
      labels: entry.labels,
      redoStack: state.redoStack.slice(0, -1),
      undoStack: [...state.undoStack, { labels: state.labels }],
    })
  },

  getFilteredLabels: () => {
    const { labels, filter, searchText } = get()
    let filtered = labels
    switch (filter) {
      case 'inputs':
        filtered = filtered.filter(l => l.portType === 'INPUT')
        break
      case 'outputs':
        filtered = filtered.filter(l => l.portType === 'OUTPUT')
        break
      case 'changed':
        filtered = filtered.filter(l => l.status === 'modified')
        break
    }
    if (searchText) {
      const lower = searchText.toLowerCase()
      filtered = filtered.filter(l =>
        l.currentLabel.toLowerCase().includes(lower) ||
        l.newLabel.toLowerCase().includes(lower) ||
        l.currentLabelLine2.toLowerCase().includes(lower) ||
        l.notes.toLowerCase().includes(lower) ||
        String(l.portNumber).includes(searchText)
      )
    }
    return filtered
  },

  getChangedLabels: () => {
    return get().labels.filter(l => l.status === 'modified')
  },
}))
