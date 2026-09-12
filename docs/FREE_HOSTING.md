# Hosting the backend online, for free

`scripts/go-online.ps1` puts the backend on the internet only while your laptop is
awake, and hands out a `*.trycloudflare.com` URL that changes every restart. This
runbook replaces it with a permanent deployment on free plans: a stable
`https://<name>.onrender.com`, reachable with your machine shut down.

Everything below is a free plan with no card required and no trial clock.

| Piece | Provider | Free allowance | Notes |
|---|---|---|---|
| API + WebSocket | [Render](https://render.com/free) web service | 512 MB RAM, 0.1 CPU, 750 instance-hours/month | Sleeps after 15 min idle; we ping it |
| Postgres | [Supabase](https://supabase.com/pricing) | 0.5 GB per active project, 2 projects | No expiry, but pauses after 7 idle days |
| Redis | [Upstash](https://upstash.com/pricing/redis) | 256 MB, 500K commands/month | Speaks the Redis protocol, works with ioredis |
| Media | Cloudinary | 25 credits/month | Optional; uploads are disabled until set |
| Email | Resend | 3K emails/month | Optional; password reset only |
| Keep-alive | GitHub Actions | Free on public repos | `.github/workflows/keep-backend-awake.yml` |

Do not use Render's own free Postgres: it expires 30 days after creation and is
deleted 14 days later. Its free Key Value store is wiped on every restart. That is
why Postgres and Redis come from Supabase and Upstash instead.

## 1. Postgres on Supabase

1. Sign up at [supabase.com](https://supabase.com), **New project**, and pick the
   region closest to the Render region you will choose in step 3.
2. Save the database password it makes you invent. It is shown once, and it is what
   replaces `[YOUR-PASSWORD]` below; if it is lost, Project Settings → Database →
   Reset database password mints a new one.
3. **Connect** in the dashboard's top bar (older layouts: Project Settings →
   Database → Connection string) → copy the **Session pooler** URI:

   ```
   postgresql://postgres.<project-ref>:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres
   ```

4. Replace `[YOUR-PASSWORD]` with the real password, brackets included. Percent-encode
   it if it contains `@ : / ? # [ ] %` — a raw `@` splits the URI in the wrong place
   and Prisma then reports an unreachable host rather than a bad password. Session
   mode needs no extra query parameters.

Take the **session** pooler specifically. The Connect panel offers three hosts and
the other two each break something here:

- **Direct** — `db.<project-ref>.supabase.co:5432`. On projects created since
  early 2024 this hostname resolves to IPv6 only, and a free Render instance has
  no IPv6 route to it. The symptom is a connect timeout or `ENETUNREACH` at boot,
  which reads like a wrong password but is not one.
- **Transaction pooler** — port `6543`. PgBouncer in transaction mode, so a
  session-level advisory lock cannot be held. The start command runs
  `npx prisma migrate deploy` on every boot and that lock is exactly what Migrate
  takes first, so the service fails to start instead of booting.
- **Session pooler** — port `5432` on the `pooler.supabase.com` host. IPv4, and
  each client keeps one server connection for the life of the session, which
  satisfies both. This is the one to paste into `DATABASE_URL`.

If you later want the transaction pooler's connection ceiling at runtime, put the
`6543` URL — with `?pgbouncer=true` appended, which stops Prisma preparing
statements the pooler cannot keep — in `DATABASE_URL`, and add
`directUrl = env("DIRECT_URL")` to the datasource block in `prisma/schema.prisma`
with the session URL there. Migrate then uses the session connection and the app
uses the pooled one. Until you need that, one Render instance opens only a handful
of Prisma connections and the single session URL is simpler.

Migrations are applied automatically on every boot by
`npx prisma migrate deploy` in the start command, so there is nothing to run by
hand — `prisma/migrations/` already holds the full history from `0_init` onward.

Supabase pauses a free project after **7 days with no activity**, and un-pausing is
a manual button in the dashboard. Nothing recovers from that on its own, so a
deployment that sits genuinely unused for a week will greet you with connection
errors until you press Restore. Real traffic counts as activity; the keep-alive in
step 4 does not, because `/health/live` deliberately touches neither Postgres nor
Redis. Step 4 has the one-variable fix if you want the ping to keep the database
awake too.

## 2. Redis on Upstash

1. Sign up at [upstash.com](https://upstash.com), create a Redis database, choose
   the region nearest Render.
2. Copy the **TCP** connection string, not the REST URL. It looks like
   `rediss://default:pw@xxx.upstash.io:6379`.
3. The `rediss://` scheme (two s's) is what switches ioredis to TLS. A plain
   `redis://` URL against Upstash hangs and the app degrades to no presence, no
   typing indicators and no cross-instance fan-out.

## 3. The backend on Render

`render.yaml` already describes the service, so this is a few clicks rather than a
form. It lives at the **git root**, one level above this `Sejilo-main/` directory,
alongside `.github/` — that is where Render and GitHub Actions look for them.

1. Push to GitHub. The remote is already set to `AashuOX/Sejilo-main`, and the
   blueprint pins `branch: master`, so Render follows the branch you work on even
   if GitHub reports `main` as the default:

   ```bash
   git push -u origin master
   ```

   Render deploys from a repository, never from your disk — anything left
   uncommitted will not be in the build.
2. [Render Dashboard](https://dashboard.render.com) → **New** → **Blueprint** →
   select the repository → **Apply**.
3. Render prompts for the values it will not invent for you:
   - `DATABASE_URL` — the Supabase session-pooler string from step 1.
   - `REDIS_URL` — the Upstash string from step 2.
   - `CLOUDINARY_URL` — leave blank for now if you have not set up Cloudinary.

   Paste these into the dashboard field, never into a chat window or a shell
   history. `GOOGLE_CLIENT_ID` is not prompted for: it is a public identifier and
   `render.yaml` already carries this project's value — see §7.
4. Wait for the first build (~3-5 min: `npm ci`, `prisma generate`, `nest build`).

`JWT_SECRET` and `TOKEN_PEPPER` are generated by Render on first apply and kept
across deploys. Do not copy the values from your local `.env` — a secret that has
lived on a laptop and in shell history should not sign production tokens.

The service URL appears at the top of the dashboard page:
`https://sejilo-backend.onrender.com`. Every later `git push origin master`
redeploys automatically.

To change the region, edit `region:` in `render.yaml` before applying — it cannot be
changed afterwards without recreating the service.

## 4. Keep it awake

Render sleeps a free service after 15 minutes without inbound traffic, and the next
request then waits about a minute. The workflow at
`.github/workflows/keep-backend-awake.yml` pings `/health/live` every 10 minutes to
prevent that. Enable it by adding one repository variable:

GitHub repo → Settings → Secrets and variables → Actions → **Variables** → New
repository variable → `BACKEND_URL` = `https://sejilo-backend.onrender.com`

Two limits to keep in mind. GitHub disables scheduled workflows after 60 days
without a commit, and cron dispatch is best-effort — under load a run can slip past
the 15-minute window. If a hard guarantee matters, point [cron-job.org](https://cron-job.org)
or UptimeRobot at the same `/health/live` URL instead; both are free.

`/health/live` returns a static body, which keeps Render awake but leaves Supabase
counting idle days (§1). To keep the database awake with the same ping, add a second
repository variable `KEEPALIVE_PATH` = `/health/ready`; that endpoint does one
`SELECT 1` and one Redis `PING` per call, so at a 10-minute cadence it spends about
4,400 of the 500K monthly Upstash commands and resets the Supabase inactivity clock
every run. The trade is that the workflow then fails — and emails you — whenever
Postgres or Redis is unreachable, which is either useful monitoring or noise
depending on your temperament.

Staying awake costs about 730 of the 750 free instance-hours in a month. That fits
one service. A second always-on free service on the same Render workspace will
exhaust the allowance and suspend both until the 1st of the next month.

## 5. Verify the deployment

From the `Sejilo-main/` directory:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-online.ps1 -BaseUrl https://sejilo-backend.onrender.com
```

It checks liveness, that Postgres and Redis are both reachable from inside the
container, that Swagger is not exposed, that a browser origin is refused, that the
WebSocket endpoint upgrades, and it runs a throwaway register/login round trip.
`-SkipAuthCheck` omits the last one if you would rather not create a test user.
Exit code is non-zero if any check fails, so it also works as a smoke test in CI.

The first call can take a minute against a sleeping instance; the script allows for
that. A `redis: unavailable` line on `/health/ready` means the URL is `redis://`
rather than `rediss://`, or the password was truncated when copied.

## 6. Point the app at it

The Flutter client resolves its API base in this order (`lib/core/api_config.dart`):
the in-app override, then the compile-time define, then the hosted instance from
`render.yaml` — `https://sejilo-backend.onrender.com`. A plain `flutter build apk`
therefore produces an app that already talks to the deployed backend; the define is
only needed to point a build somewhere else.

Per build:

```bash
flutter run --dart-define=SEJILO_API_BASE_URL=https://sejilo-backend.onrender.com
```

Or, on an already-installed build, Settings → Privacy → server URL and paste the
same URL — useful for switching a tester between the hosted backend and a laptop.

The WebSocket URL is derived from the same base, so `wss://` is picked up with no
extra configuration.

## 7. Optional integrations

All of these are added in the Render dashboard (Environment → Add environment
variable) and take effect on the next deploy. Each is inert while unset; nothing
crashes.

| Feature | Variables | Free plan |
|---|---|---|
| Media uploads | `CLOUDINARY_URL` | Cloudinary, 25 credits/month |
| Password reset email | `RESEND_API_KEY`, `PASSWORD_RESET_FROM`, `PASSWORD_RESET_URL` | Resend, 3K/month |
| Google sign-in | `GOOGLE_CLIENT_ID` (already set in `render.yaml`) | free |
| Push notifications | `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` | Firebase, free |
| SMS OTP | `SMS_PROVIDER`, `SMS_ACCOUNT_SID`, `SMS_AUTH_TOKEN`, `SMS_FROM_NUMBER` | none — Twilio charges per message |

Without an SMS provider, phone OTP codes are written to the Render log instead of
being sent, which is fine for testing and useless for real users. There is no
free SMS tier worth relying on; this is the one feature that needs money.

`GOOGLE_CLIENT_ID` is the audience every Google credential is verified against, so
it is what makes `POST /v1/auth/google` work at all: while it is unset the endpoint
answers `503 Google sign-in is not configured on this server` and the other sign-in
paths carry on. It is committed in `render.yaml` rather than prompted for, because
an OAuth client id is a public identifier that already ships inside the APK — it
must be *identical* on both sides, and leaving that to a copy-paste at apply time
is how the two drift. A mismatch shows up as `401 Google token verification failed`
with `Wrong recipient` in the Render log. There is no `GOOGLE_CLIENT_SECRET`
anywhere in this backend and nothing reads one: the app obtains the ID token and the
server only verifies its signature and audience, so no authorization-code exchange
ever happens. `docs/GOOGLE_SIGNIN.md` covers both halves and the Android OAuth
client that has to exist alongside this one.

SMTP mail cannot work on Render's free plan at all — outbound ports 25, 465 and 587
are blocked. The backend already sends over the Resend HTTPS API, so this only
matters if you were planning to swap in nodemailer.

`FCM_PRIVATE_KEY` must keep its `\n` escapes as literal backslash-n when pasted
into the dashboard field.

## What the free plan actually costs you

This is a real deployment, not a toy, but the ceilings are low and they fail in
specific ways. Render itself says free instances are not for production.

- **512 MB RAM, 0.1 CPU.** A Nest process with Prisma and firebase-admin idles
  around 200-300 MB, so there is headroom for a handful of concurrent users and
  not much more. The 0.1 CPU share is the harder limit: responses stretch under
  load long before memory runs out.
- **500K Redis commands/month** (~16K/day). Presence and typing indicators are the
  hungry callers — each WebSocket heartbeat is a `SET`. A dozen active users will
  stay well inside it; a hundred will not. Upstash stops accepting commands when
  the cap is hit, at which point presence silently degrades but chat keeps working,
  because `redis.service.ts` swallows failures by design.
- **Ephemeral filesystem.** Nothing written to disk survives a restart. All state
  must be in Postgres, Redis or Cloudinary — which it already is.
- **0.5 GB Postgres per active project.** Fine for tens of thousands of messages;
  media lives in Cloudinary, not the database. Two active projects is the cap, so
  a staging copy uses your whole allowance.
- **WebSockets drop on every restart and every redeploy.** The client needs to
  reconnect and resync through the sync endpoints rather than assume a stable
  socket.
- **A free Supabase project pauses after 7 idle days** and needs a manual Restore.
  See §1 and the `KEEPALIVE_PATH` note in §4.
- **No backups on any of these plans.** Supabase's free plan has zero retention —
  daily snapshots start at Pro, and point-in-time recovery is a paid add-on on top
  of that. Take your own `pg_dump` before anything destructive; nothing else will.

## Staying free

Two things silently turn this into a bill:

1. Adding a payment method to Render and then exceeding bandwidth or build minutes —
   overages are charged rather than blocked. Without a card on file, Render suspends
   the service instead, which is the behaviour you want here.
2. A second always-on free web service in the same workspace, which pushes the pair
   past 750 instance-hours.

Nothing in this setup requires a card. If you are asked for one, you are on the
wrong plan page.

## When to leave the free tier

Move the web service to Render's cheapest paid instance the moment real users
arrive: it removes the spin-down, the cold start and the CPU throttle in one step,
and `render.yaml` needs a single line changed (`plan:`). Supabase and Upstash can
stay free considerably longer — the first reason to pay Supabase is usually backups
rather than the 0.5 GB. `deploy/docker-compose.prod.yml` remains the path for a
single VPS with Caddy terminating TLS, if you would rather own the box.

