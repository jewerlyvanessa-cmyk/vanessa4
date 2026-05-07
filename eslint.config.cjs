const globals = require('globals');

module.exports = [
  {
    ignores: [
      'node_modules/**',
      'build/**',
      '.dart_tool/**',
      'ios/**',
      'android/**',
      'web/**',
      'macos/**',
      'linux/**',
      'windows/**',
    ],
  },
  {
    files: ['backend/**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'commonjs',
      globals: {
        ...globals.node,
      },
    },
    linterOptions: {
      reportUnusedDisableDirectives: true,
    },
    rules: {
      'no-undef': 'error',
      'no-unreachable': 'error',
      'no-constant-condition': ['error', { checkLoops: false }],
      'no-empty': ['warn', { allowEmptyCatch: true }],
      'no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_|^error$',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_|^error$',
          ignoreRestSiblings: true,
        },
      ],
      'no-console': 'off',
    },
  },
];
