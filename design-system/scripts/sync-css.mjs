// Copies the Flask portal's shipped stylesheet into the package verbatim.
// The portal is the single source of truth for the Donerup theme; this package
// never edits the CSS, it only wraps it with the webfont @import that
// build/web/app/templates/base.html supplies via <link>.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(here, '../../build/web/app/static/css/donerup.css');
const FONTS =
  "@import url('https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;800;900&family=Barlow:wght@400;500;600;700&display=swap');\n\n";

const css = readFileSync(SRC, 'utf8');
mkdirSync(resolve(here, '../src'), { recursive: true });
mkdirSync(resolve(here, '../dist'), { recursive: true });
writeFileSync(resolve(here, '../src/donerup.css'), css);
writeFileSync(resolve(here, '../dist/index.css'), FONTS + css);
console.log(`sync-css: ${css.length} bytes from ${SRC}`);
