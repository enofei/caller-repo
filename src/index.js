'use strict';

/**
 * Convert arbitrary text into a URL-safe slug.
 */
function slugify(text) {
  return String(text)
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/**
 * Simple greeting used by the CLI entry point.
 */
function greet(name) {
  return `Hello, ${name || 'world'}!`;
}

module.exports = { slugify, greet };
