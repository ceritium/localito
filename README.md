# Localito

Browse and edit a Rails app's i18n YAML files in the browser: every key side by
side across locales, what's missing, what changed since a git ref, and inline
editing that rewrites only the lines of the value you changed.

Localito is a [spinrail](https://github.com/ceritium/spinrail) app: it compiles
to a single native binary and reads the locale files on every request, so edits
made in your editor show up live.

## Usage

```sh
bin/spinrail build                 # once, in this checkout
bin/localito ~/code/my-app         # opens http://localhost:3900
bin/localito init ~/code/my-app    # writes ~/code/my-app/.localito.yml
```

```
localito [DIR] [options]        browse and edit DIR's locale files (default: .)
localito init [DIR] [options]   write DIR/.localito.yml with every setting

  -c, --config PATH   config file (default: DIR/.localito.yml)
  -p, --port PORT     first port to try (default: $LOCALITO_PORT or 3900)
      --no-open       don't open the browser
```

The first free port from 3900 up is used, so several apps can be open at once.
The server log goes to `log/localito.log` in this checkout.

## Configuration

Every setting is optional; `localito init` writes them all with their defaults.
The header shows which file is in use, and links to a page with the effective
settings and every file found.

```yaml
# Locale files to load, as globs relative to the app's root.
paths:
  - "config/locales/**/*.yml"

# Globs to leave out, e.g. vendored locales.
exclude: []

# Globs of files that are shown but never written.
readonly: []

# Column order; locales not listed follow, sorted.
locales: []

# The reference locale: first column, and what placeholders and XLIFF exports
# are checked against. Empty: the first locale.
default_locale: ""

# Git ref the working tree is compared with.
base: HEAD

# Where a new key goes when no file of its locale shares a prefix with it.
new_keys: "config/locales/%{locale}.yml"
```

## Features

- **Table or list** of keys across locales, with search over keys and values
  and a column picker.
- **Stats per locale**; click one to see what's missing there.
- **Files sidebar**: folders and file groups (`devise.en.yml` and
  `devise.es.yml` are one group, `devise.*.yml`), each with its key and
  missing counts. Clicking one scopes the list, the stats links and exports.
- **Inline editing**: click a value, `⌘↵` saves, `Esc` discards. Quoting,
  block scalars, comments, anchors, CRLF and BOM are kept; a write that would
  change any other value is refused. Values Localito can't write safely
  (arrays, Ruby objects, aliases) are shown read-only.
- **Fill in a row**: `n` / `p` jump to the next or previous missing value,
  `Enter` edits it, and saving a missing value opens the next one. `/`
  focuses the search.
- **Checks**: keys defined in more than one file (only the first is used, as
  i18n does), and values whose `%{placeholders}` differ from the reference
  locale. Both are filters and are flagged on the cell.
- **Changes** against a git ref (any branch or commit), per value.
- **Live**: the page refreshes when a file changes on disk.
- **Export** the current list as CSV (one column per locale) or XLIFF 1.2
  (reference locale to one target).
- **Import** a CSV or XLIFF back: a preview shows what is new, changed or
  can't be written, and only the checked values are written. A value changed
  since the preview is not overwritten. Empty values are skipped.

## Where a new key goes

When a key gets its first value in a locale, the file is picked in this order:

1. The counterpart of the file another locale defines it in
   (`devise.en.yml` → `devise.es.yml`, `en/admin.yml` → `es/admin.yml`), if it
   exists.
2. The file of that locale that shares the longest key prefix with it
   (`posts.index.new` goes next to `posts.index.title`).
3. That counterpart, created.
4. `new_keys`, `config/locales/<locale>.yml` by default.

Read-only files are never picked. Each value's page says where it would go.

## Development

```sh
bin/spinrail build
bin/spinrail test
```

Tests start the binary against a copy of `test/sample_app`.
