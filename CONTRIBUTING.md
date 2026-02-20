# Contributing to complete-device-management

Thank you for your interest in contributing! This document explains how to get your development environment set up and how we collaborate.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Help](#getting-help)
- [Development Setup](#development-setup)
- [Branch Naming](#branch-naming)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Testing Requirements](#testing-requirements)
- [Coding Standards](#coding-standards)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating you agree to abide by it. Please report unacceptable behaviour to the maintainers via a GitHub Discussion.

---

## Getting Help

- **Questions / ideas:** open a [GitHub Discussion](https://github.com/the78mole/complete-device-management/discussions) in the *Q&A* category.
- **Bug reports / feature requests:** use the [issue templates](https://github.com/the78mole/complete-device-management/issues/new/choose).
- **Security issues:** do **not** open a public issue. Email the maintainers directly (see the repository security policy).

---

## Development Setup

### Prerequisites

| Tool | Min. Version |
|------|-------------|
| Docker | 24.x |
| Docker Compose | 2.20 |
| Python | 3.11 |
| Node.js | 20 LTS |
| npm | 9+ |
| git | 2.40+ |

### Clone & install

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management
```

#### iot-bridge-api (Python / FastAPI)

```bash
cd glue-services/iot-bridge-api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
```

Run linters and tests:

```bash
ruff check .
mypy app
pytest --tb=short -q
```

#### terminal-proxy (Node.js / TypeScript)

```bash
cd glue-services/terminal-proxy
npm ci
npm run lint
npm test
```

#### Cloud infrastructure (Docker Compose)

```bash
cd cloud-infrastructure
cp .env.example .env   # fill in passwords
docker compose up -d
```

Validate compose files without starting containers:

```bash
docker compose -f cloud-infrastructure/docker-compose.yml config --quiet
docker compose -f device-stack/docker-compose.yml config --quiet
```

#### Documentation (MkDocs)

```bash
pip install mkdocs-material
mkdocs serve   # live-preview at http://127.0.0.1:8000
```

---

## Branch Naming

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/<short-description>` | `feat/step-ca-acme-provisioner` |
| Bug fix | `fix/<short-description>` | `fix/wireguard-ip-allocation` |
| Docs | `docs/<short-description>` | `docs/getting-started-guide` |
| Chore | `chore/<short-description>` | `chore/bump-mkdocs-material` |
| Hotfix | `hotfix/<short-description>` | `hotfix/token-expiry-crash` |

All branches should be cut from `develop`. Only `develop` → `main` merges are done by maintainers at release time.

---

## Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <short summary>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`

**Scope examples:** `iot-bridge-api`, `terminal-proxy`, `device-stack`, `step-ca`, `docs`

**Examples:**

```
feat(iot-bridge-api): add ACME device enrollment endpoint
fix(terminal-proxy): handle empty JWT header gracefully
docs(architecture): add PKI trust-chain diagram
chore(ci): pin actions/checkout to @v4
```

Keep the summary line under 72 characters. Use the body to explain *why*, not *what*.

---

## Pull Request Process

1. **Fork** the repository and create your branch from `develop`.
2. Make your changes (see testing requirements below).
3. Ensure **all CI checks pass** locally before pushing:
   ```bash
   # Python
   ruff check . && mypy app && pytest -q
   # Node
   npm run lint && npm test
   # Compose
   docker compose -f cloud-infrastructure/docker-compose.yml config --quiet
   # JSON
   find . -name "*.json" -not -path '*/.git/*' | xargs -I{} python3 -m json.tool {} > /dev/null
   ```
4. Push your branch and **open a PR** against `develop` using the PR template.
5. At least **one maintainer review** is required before merging.
6. Squash-merge is preferred to keep the history clean.

---

## Testing Requirements

| Area | Tool | Requirement |
|------|------|-------------|
| iot-bridge-api | pytest | All existing tests must pass; new endpoints need ≥ 1 happy-path + ≥ 1 error test |
| terminal-proxy | jest | All existing tests must pass; new behaviour must be covered |
| Docker Compose | `docker compose config` | Both compose files must parse without errors |
| JSON configs | `python3 -m json.tool` | All `.json` files must be valid |
| Docs | `mkdocs build --strict` | Must build without warnings |

---

## Coding Standards

### Python (iot-bridge-api)

- **Formatter/linter:** [ruff](https://docs.astral.sh/ruff/) — configuration in `pyproject.toml`
- **Type checker:** [mypy](https://mypy.readthedocs.io/) — strict mode
- All public functions must have type annotations.
- Use `httpx.AsyncClient` for all outbound HTTP calls (no `requests`).
- Inject dependencies via `fastapi.Depends` so they can be overridden in tests.

### Node.js / TypeScript (terminal-proxy)

- **Linter:** ESLint — configuration in `.eslintrc.json`
- **Compiler:** TypeScript strict mode (`tsconfig.json`)
- All injectable behaviours (auth verifier, IP resolver) must be passed as constructor/function arguments.
- Never `console.error` raw JWT payloads or credentials.

### Shell scripts

- Begin every script with `set -euo pipefail`.
- Validate required environment variables at the top before doing anything.
- Use `mktemp` for temporary files; always clean up in a `trap ... EXIT`.

### Docker

- All custom images must be based on a pinned digest or a specific version tag (not `latest` in production).
- Run processes as a non-root user where possible.
- Multi-stage builds to keep final images minimal.

### Configuration files

- All secrets go in `.env` (never committed — only `.env.example` is committed).
- Never hard-code passwords, tokens, or private keys in any checked-in file.
