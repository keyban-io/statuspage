# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a static status page for monitoring Keyban services. It's a fork of Statsig's Open-Source Status Page that displays real-time health status for multiple services including:

- Website, admin portal, docs, and loyalty demo
- Backend API and SubQL indexers (Starknet, Stellar)

The status page is entirely static (HTML/CSS/vanilla JavaScript) with automated health checks that run via GitHub Actions every 15 minutes.

## Development Commands

### Running Locally

```bash
# Simple Python server (recommended)
python3 -m http.server 8000
# Then open http://localhost:8000

# Alternative with npx
npx http-server . -p 8000
```

### Health Checks

```bash
# Run health check locally (no commit)
./health-check.sh

# Run health check with commit (used by CI)
./health-check.sh --commit

# Or via environment variable
COMMIT=true ./health-check.sh

# View logs during development
tail -F logs/*.log
```

## Architecture

### Core Files

- **index.html**: Main page template with inline templates for status squares, lines, and containers
- **index.js**: All client-side logic including data fetching, normalization, and UI rendering
- **index.css**: Styling for status indicators and layout
- **urls.cfg**: Configuration file mapping service keys to URLs (format: `key=url`)
- **health-check.sh**: Automated health monitoring script
- **logs/**: Runtime log files (not fully committed to git)

### Health Check System

**health-check.sh**: Bash script that:

1. Reads service URLs from `urls.cfg`
2. Performs up to 4 curl attempts per service (with 5s delays)
3. Considers HTTP 200, 202, 301, 302, 307 as success
4. Logs results to `logs/{key}_report.log` (format: `YYYY-MM-DD HH:MM, success|failed`)
5. Keeps last 2000 log entries per service
6. Auto-commits when `--commit` flag is used (disabled for upstream statsig-io/statuspage)

**GitHub Actions**: `.github/workflows/health-check.yml` runs `health-check.sh --commit` every 15 minutes

### Client-Side Data Flow

1. **genAllReports()** (index.js:239): Entry point
   - Fetches `urls.cfg`
   - Calls `genReportLog()` for each service

2. **genReportLog()** (index.js:3): Per-service handler
   - Fetches `logs/{key}_report.log`
   - Normalizes data via `normalizeData()`
   - Constructs status stream UI

3. **normalizeData()** (index.js:144): Data processing
   - Splits log lines by date
   - Calculates daily averages (0-1 scale)
   - Maps to relative days (0 = today)
   - Computes overall uptime percentage

4. **Status Color Logic** (index.js:44):
   - `nodata`: No health check data
   - `success`: 100% uptime (value = 1)
   - `failure`: <30% uptime
   - `partial`: 30-99% uptime

### Templating System

Custom templating via `templatize()` (index.js:71):

- Clones HTML templates from `#templates` div
- Substitutes `$variable` placeholders with parameters
- Used for status squares, containers, and streams

## Configuration

### Adding a New Service

1. Add entry to `urls.cfg`:

   ```text
   service-name=https://example.com/health
   ```

2. Run health check to generate initial logs:

   ```bash
   ./health-check.sh
   ```

3. The service will automatically appear on the status page

### Modifying Health Check Criteria

Edit `health-check.sh:52` to add/remove acceptable HTTP status codes:

```bash
if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] ...
```

### Changing Display Parameters

- **Days displayed**: Modify `maxDays` in index.js:1 (default: 30)
- **Log retention**: Modify tail value in health-check.sh:67 (default: 2000 entries)
- **Check frequency**: Modify cron in .github/workflows/health-check.yml:6 (default: `*/15 * * * *`)

## Testing

- **No automated tests**: Add tests under a `tests/` folder if introducing test tooling
- **Suggested framework**: Use `jest` for JS logic with `*.test.js` naming
- **Manual testing**: Open `index.html` in browser and run `./health-check.sh`

## Coding Conventions

- **JavaScript**: ES6, camelCase for variables/functions (e.g., `function updateStatus()`)
- **Filenames**: kebab-case (e.g., `health-check.sh`, `logo.svg`)
- **CSS classes**: kebab-case
- **Indentation**: 2 spaces
- **Linting**: Add `.prettierrc` or `.eslintrc` if adopting tooling

## Commit & Pull Request Guidelines

- **Commit messages**: Follow Conventional Commits (e.g., `feat: add incident banner`, `fix: correct health-check URL`)
- **PR checklist**: Clear description, linked issue (if any), screenshots for UI changes, run `./health-check.sh` and mention results

## Security & Important Notes

- **No build step**: This is a static site with no compilation or npm dependencies
- **Secrets**: `.env` may exist locally — keep secrets out of git
- **Logs directory**: Only automated commits from CI, avoid committing large/sensitive logs manually
- **Auto-commits**: Only occur when `health-check.sh` runs with `--commit` flag AND origin is not statsig-io/statuspage
