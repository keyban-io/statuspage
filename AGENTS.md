# Repository Guidelines

This file describes contributing practices and useful commands for the `statuspage` repo.

## Project Structure & Module Organization
- Root web app files: `index.html`, `index.js`, `index.css`.
- Static assets: `logo.svg`, `CNAME`.
- Scripts and helpers: `health-check.sh`, `tools/`.
- Runtime files: `logs/` (do not commit large / sensitive logs).

## Build, Test, and Development Commands
- Run a simple static server: `python3 -m http.server 8000` (then open `http://localhost:8000`).
- Quick alternative: `npx http-server . -p 8000`.
- Health check: `./health-check.sh` (runs project-specific checks).
- Tail logs during development: `tail -F logs/*.log`.

There is no centralized build step in this repo; if you add a toolchain, document new commands here.

## Coding Style & Naming Conventions
- JavaScript: prefer ES6, use `camelCase` for variables and functions.
- Filenames and assets: use `kebab-case` (example: `health-check.sh`, `logo.svg`).
- CSS: class names in `kebab-case`.
- Indentation: 2 spaces. Use `prettier`/`eslint` if adopted; add configs at root (`.prettierrc`, `.eslintrc`).

Example: `function updateStatus() { /* ... */ }` in `index.js`.

## Testing Guidelines
- Currently there are no automated tests. Add tests under a `tests/` folder when introducing test tooling.
- Suggested: use `jest` for JS logic, keep test filenames `*.test.js`.
- Manual checks: open `index.html` in a browser and run `./health-check.sh`.

## Commit & Pull Request Guidelines
- Commit messages: follow Conventional Commits (e.g., `feat: add incident banner`, `fix: correct health-check URL`).
- PR checklist: clear description, linked issue (if any), screenshots for UI changes, run `./health-check.sh` and mention results.

## Security & Configuration Tips
- Do not commit secrets. `.env` may exist locally — keep secrets out of git.
- If adding CI, ensure secrets are stored in the CI provider, not in the repo.

If anything in this guide becomes outdated, update `AGENTS.md` alongside code changes.

