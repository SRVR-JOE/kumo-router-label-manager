import { BrowserWindow, Menu, MenuItemConstructorOptions } from 'electron'

export function createMenu(mainWindow: BrowserWindow): void {
  const template: MenuItemConstructorOptions[] = [
    {
      label: 'File',
      submenu: [
        {
          label: 'New',
          accelerator: 'CmdOrCtrl+N',
          click: () => mainWindow.webContents.send('menu:new'),
        },
        {
          label: 'Open...',
          accelerator: 'CmdOrCtrl+O',
          click: () => mainWindow.webContents.send('menu:open'),
        },
        {
          label: 'Save',
          accelerator: 'CmdOrCtrl+S',
          click: () => mainWindow.webContents.send('menu:save'),
        },
        {
          label: 'Save As...',
          accelerator: 'CmdOrCtrl+Shift+S',
          click: () => mainWindow.webContents.send('menu:save-as'),
        },
        { type: 'separator' },
        {
          label: 'Create Template...',
          click: () => mainWindow.webContents.send('menu:create-template'),
        },
        { type: 'separator' },
        {
          label: 'Exit',
          accelerator: 'CmdOrCtrl+Q',
          click: () => mainWindow.close(),
        },
      ],
    },
    {
      label: 'Router',
      submenu: [
        {
          label: 'Connect...',
          click: () => mainWindow.webContents.send('menu:connect'),
        },
        {
          label: 'Disconnect',
          click: () => mainWindow.webContents.send('menu:disconnect'),
        },
        { type: 'separator' },
        {
          label: 'Download Labels',
          click: () => mainWindow.webContents.send('menu:download'),
        },
        {
          label: 'Upload Labels',
          click: () => mainWindow.webContents.send('menu:upload'),
        },
        { type: 'separator' },
        {
          label: 'Crosspoint Matrix',
          click: () => mainWindow.webContents.send('menu:crosspoint'),
        },
      ],
    },
    {
      label: 'Tools',
      submenu: [
        {
          label: 'Find & Replace',
          accelerator: 'CmdOrCtrl+F',
          click: () => mainWindow.webContents.send('menu:find-replace'),
        },
        {
          label: 'Auto-Number',
          click: () => mainWindow.webContents.send('menu:auto-number'),
        },
        {
          label: 'Bulk Operations',
          click: () => mainWindow.webContents.send('menu:bulk-ops'),
        },
        { type: 'separator' },
        {
          label: 'Statistics',
          click: () => mainWindow.webContents.send('menu:statistics'),
        },
        { type: 'separator' },
        {
          label: 'Settings',
          click: () => mainWindow.webContents.send('menu:settings'),
        },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        {
          label: 'Undo',
          accelerator: 'CmdOrCtrl+Z',
          click: () => mainWindow.webContents.send('menu:undo'),
        },
        {
          label: 'Redo',
          accelerator: 'CmdOrCtrl+Y',
          click: () => mainWindow.webContents.send('menu:redo'),
        },
        { type: 'separator' },
        { label: 'Cut', accelerator: 'CmdOrCtrl+X', role: 'cut' },
        { label: 'Copy', accelerator: 'CmdOrCtrl+C', role: 'copy' },
        { label: 'Paste', accelerator: 'CmdOrCtrl+V', role: 'paste' },
        { label: 'Select All', accelerator: 'CmdOrCtrl+A', role: 'selectAll' },
      ],
    },
    {
      label: 'Help',
      submenu: [
        {
          label: 'About Helix Label Manager',
          click: () => mainWindow.webContents.send('menu:about'),
        },
      ],
    },
  ]

  const menu = Menu.buildFromTemplate(template)
  Menu.setApplicationMenu(menu)
}
