import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    react(),
  ],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./dashboard/__tests__/setup.js'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura'],
      // Relative to Vite's root (app/frontend), so this lands at
      // app_core/coverage-frontend/ — see agent/styleguides/ci-and-coverage.md.
      reportsDirectory: '../../coverage-frontend',
    },
  },
})
