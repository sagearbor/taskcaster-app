'use strict';

/** Flat ESLint config for the montage functions (CommonJS, Node 20). */
module.exports = [
  {
    files: ['src/**/*.js', 'test/**/*.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'commonjs',
      globals: {
        require: 'readonly',
        module: 'writable',
        exports: 'writable',
        process: 'readonly',
        console: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
      },
    },
    linterOptions: {reportUnusedDisableDirectives: true},
    rules: {
      'no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
      'no-undef': 'error',
      'no-console': 'off',
      eqeqeq: ['error', 'smart'],
      'prefer-const': 'error',
      'no-var': 'error',
      'no-await-in-loop': 'warn',
      'object-shorthand': 'error',
      'no-return-await': 'error',
    },
  },
];
