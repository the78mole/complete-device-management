# Zensical Skill – CDM Platform Docs

> **Scope**: Gives GitHub Copilot precise knowledge of the Zensical documentation setup in
> this repository so it can make correct edits to `zensical.toml`, add pages, adjust navigation,
> and help with theming without ever reverting to the legacy MkDocs workflow.

---

## 1. What is Zensical?

Zensical is a modern static-site generator that is the **successor to MkDocs + Material for
MkDocs**.  Configuration is in TOML (`zensical.toml`), not YAML.  The output is a static
`site/` directory identical in structure to MkDocs output, so the same GitHub Pages deployment
pipeline works.

| Property | Value |
|---|---|
| Package | `zensical` (PyPI) |
| Version | `>=0.0.23` (see `docs/requirements.txt`) |
| Config file | `zensical.toml` (repo root) |
| Docs source | `docs/` |
| Build output | `site/` (.gitignore-d) |
| CLI | `python3 -m zensical build --clean` |
| Serve locally | `python3 -m zensical serve` |

> **Never create or restore a `mkdocs.yml`** — it was intentionally deleted.  All doc tooling
> must use `zensical.toml` and the `zensical` CLI.

---

## 2. Configuration file (`zensical.toml`)

The file lives at the **repo root** (`zensical.toml`).

### 2.1 Top-level `[project]` keys

| Key | Type | Purpose |
|---|---|---|
| `site_name` | string | Title in browser tab + header |
| `site_description` | string | `<meta name="description">` for SEO |
| `site_author` | string | `<meta name="author">` |
| `site_url` | string | Canonical URL (important for sitemap) |
| `repo_url` | string | Shown as repo link in header |
| `repo_name` | string | Display name for the repo link |
| `edit_uri` | string | GitHub edit-page URI prefix |
| `docs_dir` | string | Source directory (default `docs`) |
| `copyright` | string | HTML fragment shown in footer |
| `nav` | array of tables | Explicit navigation tree (optional) |
| `extra_css` | string array | Extra CSS files relative to `docs_dir` |
| `extra_javascript` | string array | Extra JS files relative to `docs_dir` |

### 2.2 Navigation syntax

Navigation is defined as a TOML **array of inline tables**, mixing leaves (page) and
nested sections.  Every navigation entry is a one-key inline table.

```toml
nav = [
  { "Home" = "index.md" },                           # leaf page
  { "Installation" = [                               # section
    { "Overview" = "installation/index.md" },
    { "Provider Stack" = "installation/provider-stack.md" },
  ]},
]
```

- **Paths** are relative to `docs_dir`.
- **Sections** can be nested arbitrarily.
- If `nav` is omitted Zensical derives structure from the directory tree.

### 2.3 Theme section

```toml
[project.theme]
language = "en"                 # locale for UI labels
# variant = "classic"          # uncomment for traditional Material look
features = [...]                # list of feature toggle strings (see §2.4)

[[project.theme.palette]]       # light palette (TOML array-of-tables)
scheme = "default"
toggle.icon  = "lucide/sun"
toggle.name  = "Switch to dark mode"

[[project.theme.palette]]       # dark palette
scheme = "slate"
toggle.icon  = "lucide/moon"
toggle.name  = "Switch to light mode"

[project.theme.icon]            # optional icon overrides
logo = "lucide/cpu"
repo = "fontawesome/brands/github"

[project.theme.font]            # optional font overrides (Google Fonts)
text = "Inter"
code = "JetBrains Mono"
```

### 2.4 Active feature toggles (CDM)

The following features are currently enabled in `zensical.toml`:

```text
content.action.edit          → "Edit this page" button (uses edit_uri)
content.action.view          → "View source" button
content.code.annotate        → code annotations with tooltips
content.code.copy            → copy-to-clipboard button in code blocks
content.code.select          → line-range selection in code blocks
content.footnote.tooltips    → inline footnote hover tooltips
content.tabs.link            → linked content tabs (all same-label tabs switch together)
content.tooltips             → improved link tooltips
navigation.footer            → prev/next page links in footer
navigation.indexes           → section index pages (section title links to index.md)
navigation.instant           → SPA-style client-side navigation
navigation.instant.prefetch  → prefetch on link hover
navigation.path              → breadcrumb above page title
navigation.sections          → top-level sections as sidebar groups
navigation.tabs              → top-level sections as horizontal tabs (≥1220 px)
navigation.tabs.sticky       → sticky tabs
navigation.top               → back-to-top button
navigation.tracking          → URL hash = active anchor
search.highlight             → highlight search terms after following a result
```

### 2.5 Social links

```toml
[[project.extra.social]]
icon = "fontawesome/brands/github"
link = "https://github.com/the78mole/complete-device-management"
```

---

## 3. Markdown features

Zensical supports the same Markdown extensions as MkDocs + Material without explicit
`markdown_extensions` configuration.  All of the following work out of the box:

| Feature | Syntax |
|---|---|
| Admonitions | `!!! note`, `!!! warning`, `!!! tip`, `!!! info`, `!!! danger` |
| Collapsible admonitions | `??? note "Title"` |
| Mermaid diagrams | ` ```mermaid ` fenced code block |
| Code highlighting | fenced blocks with language tag, e.g. ` ```python ` |
| Code annotations | `# (1)` inside code + `1. Explanation` below |
| Content tabs | `=== "Tab A"` / `=== "Tab B"` |
| Task lists | `- [x] done`, `- [ ] todo` |
| Tables | GitHub Flavored Markdown tables |
| Footnotes | `[^1]` / `[^1]: text` |
| Table of contents | automatic, `##` headings generate anchors |
| Attribute lists | `{ .class #id }` after elements |
| Emoji/icons | `:material-check:`, `:fontawesome-brands-github:`, `:lucide-cpu:` |

> **No `markdown_extensions` section needed** — Zensical handles all of this automatically.

---

## 4. GitHub Actions deployment

File: `.github/workflows/docs.yml`

The workflow:
1. Installs Zensical via `pip install -r docs/requirements.txt`
2. Runs `zensical build` (clean build)
3. Uploads `site/` as a GitHub Pages artifact
4. Deploys to GitHub Pages on pushes to `main`

```yaml
- name: Install Zensical
  run: pip install -r docs/requirements.txt

- name: Build
  run: zensical build
```

> `docs/requirements.txt` pins `zensical>=0.0.23`.  Update this line to bump the version.

---

## 5. Current documentation structure

```
docs/
├── index.md                               # Home
├── NOTES.md                               # Not in nav (internal notes)
├── installation/
│   ├── index.md                           # Installation overview
│   ├── provider-stack.md                  # Provider-Stack setup
│   ├── tenant-stack.md                    # Tenant-Stack setup
│   ├── device-stack.md                    # Device-Stack setup
│   └── cloud-infrastructure.md            # Legacy (not in nav, kept for reference)
├── getting-started/
│   ├── index.md
│   ├── first-device.md
│   └── first-ota-update.md
├── architecture/
│   ├── index.md
│   ├── stack-topology.md
│   ├── pki.md
│   ├── iam.md
│   └── data-flow.md
├── workflows/
│   ├── device-provisioning.md
│   ├── ota-updates.md
│   ├── remote-access.md
│   └── monitoring.md
└── use-cases/
    ├── index.md
    ├── tenant-onboarding.md
    ├── fleet-management.md
    ├── security-incident-response.md
    └── troubleshooting.md
```

Pages not listed in `nav` are still built; they just don't appear in the sidebar.

---

## 6. Common tasks

### Add a new page

1. Create `docs/<section>/new-page.md`
2. Add an entry to `nav` in `zensical.toml`:
   ```toml
   { "My New Page" = "<section>/new-page.md" },
   ```
3. Run `python3 -m zensical build --clean` to verify.

### Add a new top-level section

```toml
nav = [
  ...
  { "New Section" = [
    { "Overview" = "new-section/index.md" },
    { "Detail" = "new-section/detail.md" },
  ]},
]
```

### Enable an additional feature toggle

Add the feature string to the `features` list in `[project.theme]`:

```toml
features = [
  ...
  "navigation.expand",   # ← new: expand all nav sections by default
]
```

### Change the color palette

```toml
[project.theme]
# use "classic" for traditional Material for MkDocs look
variant = "classic"

[[project.theme.palette]]
scheme  = "default"
primary = "indigo"
accent  = "indigo"
toggle.icon = "lucide/sun"
toggle.name = "Switch to dark mode"
```

### Add extra CSS

```toml
[project]
extra_css = ["stylesheets/extra.css"]
```

Then create `docs/stylesheets/extra.css`.

### Build and preview locally

```bash
# Build once
python3 -m zensical build --clean

# Live-reload dev server
python3 -m zensical serve
# → serves on http://127.0.0.1:8000
```

---

## 7. Migration notes (from MkDocs)

The CDM docs were migrated from MkDocs + Material for MkDocs to Zensical in February 2026
because MkDocs 2.0 broke compatibility with Material for MkDocs.

| MkDocs concept | Zensical equivalent |
|---|---|
| `mkdocs.yml` | `zensical.toml` |
| `site_name:` (YAML) | `site_name = "…"` (TOML) |
| `theme.features:` list | `features = […]` in `[project.theme]` |
| `theme.palette:` list | `[[project.theme.palette]]` TOML array-of-tables |
| `nav:` list of `{Title: file}` | `nav = [{ "Title" = "file.md" }, …]` |
| `extra.social:` | `[[project.extra.social]]` |
| `markdown_extensions:` | Not needed (all extensions built-in) |
| `plugins: - search` | Built-in, no config needed |
| `!!python/name:…` Jinja2/Python hooks | Not supported; use standard Markdown |
| `run: mkdocs build` | `run: zensical build` |
