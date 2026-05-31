# gisila-panel · frontend

Next.js 15 (App Router) · TypeScript · Tailwind CSS · shadcn/ui · SWR ·
Recharts · Sonner toasts.

## Development

There is **no need to install Node, pnpm, or Next.js on your laptop**.
The frontend runs inside the gisila-panel docker-compose stack:

```bash
cd .. && docker compose up frontend
# or, for the whole stack:
cd .. && docker compose up
```

Open <http://localhost:3000>. Edits to `app/`, `components/`, `lib/` etc.
hot-reload through the bind-mounted source tree.

### Env vars

| Variable               | Default                  | Used by         |
| ---------------------- | ------------------------ | --------------- |
| `NEXT_PUBLIC_API_URL`  | `http://localhost:8000`  | Browser fetches |
| `NEXT_PUBLIC_WS_URL`   | `ws://localhost:8000`    | Live-log WS     |
| `INTERNAL_API_URL`     | `http://api:8000`        | Next.js SSR     |

## Bare-metal install (optional)

If you really want to run the frontend outside Docker:

```bash
pnpm install
cp .env.example .env.local
pnpm dev
```

## Routes

| Route | What it does |
|-------|--------------|
| `/` | Marketing landing page |
| `/login`, `/register` | Auth |
| `/dashboard` | Overview cards & recent apps |
| `/apps` | All apps |
| `/apps/new` | Create app wizard |
| `/apps/[id]` | Tabs: overview · deployments · environment · domains · logs (live WS) · metrics |
| `/teams` | Teams + create |
| `/domains` | Cross-app domain overview |
| `/activity` | Recent deployments across all apps |
| `/settings` | Profile + SSH keys |
| `/settings/tokens` | API tokens |

## Live logs

The logs tab opens a WebSocket against
`NEXT_PUBLIC_WS_URL/ws/apps/<id>/logs` and authenticates with the JWT in
`localStorage`. The first frame sent is `{ token, appId }`; subsequent frames
are journald lines streamed via Redis pubsub.
