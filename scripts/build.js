'use strict';

const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const srcDir = path.join(root, 'src');
const distDir = path.join(root, 'dist');

fs.mkdirSync(distDir, { recursive: true });

const files = fs
  .readdirSync(srcDir)
  .filter((file) => file.endsWith('.js'))
  .sort();

if (files.length === 0) {
  console.error('Build failed: no source files found in src/');
  process.exit(1);
}

const bundle = files
  .map((file) => `// --- src/${file} ---\n${fs.readFileSync(path.join(srcDir, file), 'utf8')}`)
  .join('\n');

fs.writeFileSync(path.join(distDir, 'index.js'), `'use strict';\n${bundle}\n`);

fs.writeFileSync(
  path.join(distDir, 'build-info.json'),
  JSON.stringify({ builtAt: new Date().toISOString(), node: process.version, files }, null, 2)
);

console.log(`Built ${files.length} file(s) -> dist/index.js`);
