/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/renderer/**/*.{html,tsx,ts}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        helix: {
          bg: 'rgb(30, 25, 40)',
          surface: 'rgb(40, 35, 55)',
          'surface-hover': 'rgb(50, 45, 65)',
          border: 'rgb(70, 60, 90)',
          accent: '#7B2FBE',
          'accent-hover': '#9040DE',
          text: '#E8E0F0',
          'text-muted': '#9A8FB0',
          'text-dim': '#6B5F80',
          success: '#4ADE80',
          error: '#F87171',
          warning: '#FBBF24',
        },
        kumo: {
          1: '#fe0000', // Red
          2: '#f76700', // Orange
          3: '#d7af00', // Yellow
          4: '#009af4', // Blue
          5: '#00a263', // Teal
          6: '#60b71f', // Light Green
          7: '#3a5ef6', // Indigo
          8: '#8100f4', // Purple
          9: '#f30088', // Pink
        },
        'kumo-idle': {
          1: '#cb7676',
          2: '#e6a52e',
          3: '#d9cb7e',
          4: '#87b4c8',
          5: '#64c896',
          6: '#ade68e',
          7: '#7888cb',
          8: '#9b8ce1',
          9: '#c84b91',
        },
      },
      fontFamily: {
        mono: ['Consolas', 'Monaco', 'Courier New', 'monospace'],
      },
    },
  },
  plugins: [],
}
