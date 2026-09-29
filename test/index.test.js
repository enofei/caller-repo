'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { slugify, greet } = require('../src/index');

test('slugify converts text to a URL-safe slug', () => {
  assert.equal(slugify('Hello, World!'), 'hello-world');
  assert.equal(slugify('  CI/CD & Testing  '), 'ci-cd-testing');
});

test('slugify strips leading and trailing separators', () => {
  assert.equal(slugify('---node---'), 'node');
});

test('greet falls back to a default name', () => {
  assert.equal(greet('Ada'), 'Hello, Ada!');
  assert.equal(greet(), 'Hello, world!');
});
