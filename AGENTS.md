# AGENTS.md

Assumption: `uv` and `npm` are already installed in the system.

## Python on macOS: Use `uv` (not `pip`)

### 1) Initialize Python project
```bash
uv init --bare --python 3.11
```

### 2) Install baseline Python dependencies (main scenarios)
```bash
uv add \
  mcp \
  defusedxml \
  lxml \
  pyyaml \
  openpyxl \
  pypdf \
  pdfplumber \
  reportlab \
  "markitdown[pptx]" \
  playwright
```

### 3) How to run Python skill scripts
```bash
# Always use uv run
uv run python .agents/skills/pptx/scripts/thumbnail.py input.pptx
uv run python .agents/skills/docx/scripts/office/validate.py input.docx
uv run python .agents/skills/webapp-testing/scripts/with_server.py --help
```

## npm / JavaScript

### 4) Initialize npm project for JS scripts
```bash
npm init -y
```

### 5) Install JS packages expected by skills
```bash
# Recommended: local install in project (not global)
npm install docx pptxgenjs react react-dom react-icons sharp
```

### 6) How to run JS scripts
```bash
# Option 1: direct run
node script.js

# Option 2: via package.json scripts
npm pkg set scripts.run-js="node script.js"
npm run run-js
```

### 7) Quick smoke check for JS dependencies
```bash
node -e "require('docx'); require('pptxgenjs'); require('react'); require('react-dom/server'); require('react-icons/fa'); require('sharp'); console.log('ok')"
```

## Quick Notes for Agents

- On macOS, do not use `pip install ...` in instructions. Use `uv add ...` / `uv run ...`.
- Run Python commands via `uv run` to keep environment behavior consistent.
- For JS, ensure `package.json` exists first, then `npm install`, then `node ...` or `npm run ...`.
- If a command fails with a missing external binary, treat it as an advanced path limitation and continue with the Python/npm baseline flow where possible.
