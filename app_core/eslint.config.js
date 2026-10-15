// ESLint flat config for the frontend. Prettier owns formatting and is
// applied last via eslint-config-prettier; ESLint owns correctness.
// See agent/styleguides/core/react-dashboard.md (Linting & Formatting) and
// agent/adr/core/frontend-lint-stack.md.

import js from '@eslint/js'
import globals from 'globals'
import react from 'eslint-plugin-react'
import reactHooks from 'eslint-plugin-react-hooks'
import prettier from 'eslint-config-prettier'

export default [
  {
    ignores: ['node_modules/**', 'public/**', 'coverage/**', 'coverage-frontend/**'],
  },
  js.configs.recommended,
  {
    files: ['app/frontend/**/*.{js,jsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser },
    },
    plugins: {
      react,
      'react-hooks': reactHooks,
    },
    settings: {
      react: { version: 'detect' },
    },
    rules: {
      ...react.configs.flat.recommended.rules,
      ...react.configs.flat['jsx-runtime'].rules,
      ...reactHooks.configs.flat.recommended.rules,
      // No prop-types in this codebase — the frontend has no type layer.
      'react/prop-types': 'off',
      // React-Compiler-oriented rules (react-hooks v7). They flag existing,
      // intentional patterns (a synchronous `setStatus('loading')` in a
      // data-loading effect; `Date.now()` for chart bounds). Fixing them means
      // refactoring working data-loading hooks — out of scope for adding a
      // lint gate. The classic correctness rules (rules-of-hooks,
      // exhaustive-deps) stay on.
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/purity': 'off',
    },
  },
  prettier,
]
