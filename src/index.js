'use strict';

function slugify(text) {
  return String(text)
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function greet(name) {
  return `Hello, ${name || 'world'}!`;
}

module.exports = { slugify, greet };
