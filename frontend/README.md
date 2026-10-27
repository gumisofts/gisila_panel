# gisila-panel · frontend

React 19 · Vite · TypeScript · IBM Carbon · react-router · SWR · Recharts.

The build is a static single-page app written to `../backend/web/`, which
the Dart API server serves (with a strict Content-Security-Policy, see
`backend/lib/infra/ui_headers.dart`). Pages are code-split per route.

## Development

With the docker-compose stack, `frontend-build` runs `vite build --watch`
into `backend/web/`:

```bash
cd .. && docker compose up
```

Or run the Vite dev server against an API on `localhost:8000` (it proxies
the API prefixes and `/ws`, see `vite.config.ts`):

```bash
pnpm install
pnpm dev          # http://localhost:5173
pnpm typecheck
pnpm lint
```

When building by hand, build somewhere else first (`pnpm build --outDir
/tmp/web`): `backend/web/` is tracked and emptied by the build.

### Env vars

Only for running the UI on a different origin than the API; the values are
baked into the bundle, so never set them for a build that lands in
`backend/web/`.

| Variable       | Example                 | Used for        |
| -------------- | ----------------------- | --------------- |
| `VITE_API_URL` | `http://localhost:8000` | API requests    |
| `VITE_WS_URL`  | `ws://localhost:8000`   | Live-log WS (`/ws` is appended) |

## Routes

| Route | What it does |
|-------|--------------|
| `/` | Landing; links to `/dashboard` or `/login` |
| `/login` | Sign in (accounts are created by a superuser under Settings → Users) |
| `/dashboard` | Overview cards & recent apps |
| `/apps`, `/apps/new`, `/apps/:id` | Apps, the create wizard, and an app's tabs (overview, deployments, environment, domains, logs, console, metrics, storage, settings) |
| `/projects`, `/teams` | Projects; teams with quotas |
| `/domains`, `/databases`, `/storage`, `/mail`, `/services`, `/runtimes` | Hosted resources |
| `/activity`, `/notifications` | Audit log and alerts |
| `/settings/...` | Profile, security, SSH keys, API tokens, users, notifications |

## Live logs

Log sockets (`lib/log-socket.ts`) connect to `/ws/...`, send
`{ token, ...ids }` as the first frame, and wait for `{ ready: true }`
before showing "Live". An `{ error }` frame ends the socket; an auth error
signs you out.
