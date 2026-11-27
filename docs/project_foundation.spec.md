---
title: Project Foundation
status: review
author: Antoine Bouteiller
date: 2026-11-27
module:
  - app/backend
  - app/frontend
  - proto
  - go.mod
  - flake.nix
  - .golangci.yml
  - buf.yaml
  - buf.gen.yaml
related:
  - app/backend/internal/domains/downloadclients/download_clients.spec.md
---

## Why

Armadarr replaces the \*arr stack and Autoscan with one Go server and a Svelte client. Most of its
work is long-running background work against flaky outside services: polling download clients,
syncing indexers, and scanning libraries. Before the first feature lands, the project needs a fixed
layout, one database access path, one way to run background work, and one API contract that the
server and the browser both compile against. Without these, each feature would invent its own.

- `[G-1]` Make the owner and role of every source module clear from its path.
- `[G-2]` Give every domain one database access path behind interfaces it owns, so another
  database means another implementation of those interfaces and no change to their callers.
- `[G-3]` Run recurring and per-key background work under a context owned by the process, so
  shutdown stops it.
- `[G-4]` Generate the server and browser sides of the API from one definition, so a contract
  change that one side does not follow fails to compile.
- `[NG-1]` Authentication on the admin API. Deployment keeps it reachable only over Tailscale.
- `[NG-2]` An ORM or query builder. Queries are SQL files.
- `[NG-3]` Supporting a second database now. Only PostgreSQL ships.
- `[NG-4]` Reusing Autoscan's TypeScript code. Each Autoscan feature is re-implemented in Go under
  its own spec.

## Design

- `[PI-1]` One owner per module: a package lives in the narrowest partition that owns its
  responsibility.
- `[PI-2]` The context owns lifetime: every goroutine, connection and server started by the
  process is tied to the root context in `app/backend/cmd/armadarr` and waited for before `run` returns.
- `[PI-3]` Dialect at the edge: only `app/backend/internal/database` and the Postgres store packages know the
  driver. Everything else depends on store interfaces.
- `[PI-4]` Contract first: an API change starts in `proto/`, and both sides regenerate from it.

| Decision                   | Choice                                                                                                                                                                                             | Rationale                                                                                                                                                                                                                                |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[KD-1]` Source partitions | The tree in `[CT-1]`: the Go server under `app/backend/`, the client under `app/frontend/`, the contract under `proto/`. `go.mod` sits at the root.                                                | Each app is found under `app/`. A root `go.mod` lets `app/frontend/embed.go` embed the client build, which a module rooted at `app/backend` could not reach. `app/backend/internal/` keeps the server packages private to `app/backend`. |
| `[KD-2]` Database access   | A `pgxpool.Pool` from `app/backend/internal/database`. Each domain declares a `Store` interface in its own types, and its `postgres/` subpackage implements it (`[CT-2]`).                         | The interface is the abstraction that `[G-2]` asks for. pgx is the most complete PostgreSQL driver for Go and needs no cgo.                                                                                                              |
| `[KD-3]` Typed queries     | Queries are SQL in `app/backend/internal/domains/<name>/postgres/queries.sql`. sqlc generates their Go functions and row types, using the migrations as the schema.                                | Column drift fails code generation, not a runtime decode.                                                                                                                                                                                |
| `[KD-4]` Migrations        | goose over SQL files embedded from `app/backend/internal/database/migrations/` (`[CT-4]`). They run at startup under a PostgreSQL advisory lock.                                                   | The binary carries its migrations. The lock makes concurrent starts safe.                                                                                                                                                                |
| `[KD-5]` Background work   | `app/backend/internal/task` runs a recurring task until its context ends (`[CT-5]`). Per-key tasks run in a `task.Group` owned by the service that keys them.                                      | One runner gives every task the same failure, panic and shutdown behavior. `testing/synctest` tests the timing without real waits.                                                                                                       |
| `[KD-6]` Feature shape     | A feature package exports a constructor that takes its dependencies as arguments and returns its Connect handler and, when it has background work, a `Run(ctx)` method.                            | `app/backend/cmd/armadarr` wires every feature explicitly. There is no registry and no `init()` side effect.                                                                                                                             |
| `[KD-7]` Configuration     | `config.Load` reads the environment once at startup into a struct passed down by value. A secret `X` is also accepted as a file path in `X_FILE`.                                                  | Matches Autoscan's `*_FILE` convention for NixOS secret files, without global state.                                                                                                                                                     |
| `[KD-8]` Database in tests | A `TestMain` helper in `app/backend/internal/database/dbtest` starts a throwaway cluster with `initdb` and `pg_ctl` from the dev shell. Each test gets a database cloned from a migrated template. | Store tests run real SQL. Per-test databases let tests run in parallel. CI already runs inside `nix develop`, so it needs no service container.                                                                                          |
| `[KD-9]` Import boundaries | golangci-lint `depguard` enforces the Go rules in `[CT-1]`, and the `vp check` lint config enforces the client rule.                                                                               | The boundaries hold without review discipline.                                                                                                                                                                                           |
| `[KD-10]` API contract     | Connect RPC defined in `proto/`. `buf generate` writes Go handlers and clients to `app/backend/internal/gen` and a TypeScript client to `app/frontend/src/gen` (`[CT-7]`).                         | Both sides compile against one definition. Connect works over HTTP/1.1, including server streaming, so the browser needs no gRPC-Web proxy.                                                                                              |
| `[KD-11]` Client           | A Svelte 5 single-page app built by Vite+ into `app/frontend/dist/client` and embedded into the binary through `app/frontend/embed.go` (`[CT-8]`).                                                 | One static binary serves the client and the API. Vite+ provides the build, tests, formatting and linting.                                                                                                                                |

## Outcome

- `[SO-1]` Domains read and write PostgreSQL through store interfaces, with query results typed by
  sqlc and driver errors translated into domain errors. — demonstrated by `[VC-1]`
- `[SO-2]` A store method that fails halfway leaves no partial write. — demonstrated by `[VC-2]`
- `[SO-3]` Startup applies pending migrations once before the HTTP server listens, even when two
  processes start together. — demonstrated by `[VC-3]`
- `[SO-4]` A recurring task survives a failed or panicking run and stops when its context ends. —
  demonstrated by `[VC-4]`
- `[SO-5]` The NixOS module passes PostgreSQL settings and a password file to the service. —
  demonstrated by `[VC-5]`
- `[SO-6]` The browser and the server reach each other only through clients generated from
  `proto/`. — demonstrated by `[VC-6]`
- `[SO-7]` One binary serves the client and the API, and exposes no directory listing. —
  demonstrated by `[VC-7]`

## Contracts

### [CT-1] Source layout and import rules

Kind: boundary · Anchor: null

```text
app/
├── backend/
│   ├── cmd/armadarr/            composition root: config, database, migrations, features, HTTP server
│   └── internal/
│       ├── config/              environment and secret files
│       ├── database/            pgx pool, migrator, migrations/*.sql, dbtest/ for tests
│       ├── domains/<name>/      cross-feature business services and their Store interface
│       │   └── postgres/        the Store implementation: queries.sql, sqlc output, store.go
│       ├── features/<name>/     Connect handlers and background tasks of one capability
│       ├── integrations/<vendor>/ vendor HTTP clients and their response types
│       ├── server/              HTTP composition: /api and the client
│       ├── task/                background task runner
│       └── gen/                 written by buf generate
└── frontend/                    self-contained pnpm project: package.json, vite.config.ts, tsconfig.json
    ├── index.html
    ├── src/                     Svelte app; src/gen is written by buf generate
    └── embed.go                 embeds dist/client
proto/armadarr/v1/               API contract
vendor/                          Go modules written by go mod vendor
go.mod                           one Go module for app/backend and app/frontend/embed.go
```

| Code                                                                                            | May not import                                                                                 |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `app/backend/internal/integrations`                                                             | `app/backend/internal/domains`, `app/backend/internal/features`, `app/backend/internal/server` |
| `app/backend/internal/domains`                                                                  | `app/backend/internal/features`, `app/backend/internal/server`                                 |
| `app/backend/internal/features/X`                                                               | `app/backend/internal/features/Y`                                                              |
| everything except `app/backend/internal/database` and `app/backend/internal/domains/*/postgres` | `github.com/jackc/pgx`                                                                         |
| `app/frontend/src`                                                                              | a path two or more directories up; use `@/`                                                    |

Go packages are single lowercase words, and Go files are snake_case. TypeScript and Svelte files
are snake_case. Tests sit beside the code they test: `_test.go` for Go and `*.test.ts` for the
client.

### [CT-2] Database pool and stores

Kind: api · Anchor: null

```go
// app/backend/internal/database/database.go
func Open(ctx context.Context, cfg config.Postgres) (*pgxpool.Pool, error)

// app/backend/internal/domains/<name>/store.go
type Store interface { /* methods in domain types, one per atomic operation */ }

// app/backend/internal/domains/<name>/postgres/store.go
func New(pool *pgxpool.Pool) <name>.Store
```

- A store method is atomic. A method with several writes runs them in one `pgx.BeginFunc`
  transaction.
- The Postgres store translates SQLSTATE `23505` into the domain's conflict error and no rows into
  its not-found error. Callers never inspect pgx errors.
- `app/backend/cmd/armadarr` closes the pool after the HTTP server and every task have stopped.

### [CT-3] Database configuration

Kind: config · Anchor: null

| Variable            | Required | Meaning                                                               |
| ------------------- | -------- | --------------------------------------------------------------------- |
| `POSTGRES_HOST`     | yes      | host name, or a directory for a Unix socket when it starts with `/`   |
| `POSTGRES_PORT`     | no       | default `5432`                                                        |
| `POSTGRES_DATABASE` | yes      |                                                                       |
| `POSTGRES_USERNAME` | yes      |                                                                       |
| `POSTGRES_PASSWORD` | no       | read from the file named by `POSTGRES_PASSWORD_FILE` when that is set |

`services.armadarr` in `flake.nix` gains `postgres.{host,port,database,user}` and
`secrets.postgresPasswordFile`, mapped onto these variables.

### [CT-4] Migrations

Kind: api · Anchor: null

```go
// app/backend/internal/database/migrate.go
//go:embed migrations/*.sql
var migrations embed.FS

// Migrate applies pending migrations while holding a session advisory lock.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error
```

A migration is one file `app/backend/internal/database/migrations/<NNNNN>_<name>.sql` with goose `Up`
annotations. Migrations are append-only and have no `Down` section. sqlc reads the same files as
its schema.

### [CT-5] Background tasks

Kind: api · Anchor: null

```go
// app/backend/internal/task/task.go
type Task struct {
	Name    string
	Every   time.Duration                 // wait after a successful run
	Backoff func(failures int) time.Duration // wait after the nth consecutive failure; nil means Every
	Run     func(ctx context.Context) error
}

// Run runs t until ctx is done.
func Run(ctx context.Context, t Task)

// Group runs at most one task per key.
type Group[K comparable] struct{ /* … */ }
func NewGroup[K comparable](ctx context.Context) *Group[K]
func (g *Group[K]) Start(key K, t Task) // stops the task already running under key first
func (g *Group[K]) Stop(key K)
func (g *Group[K]) Wait()               // returns once ctx is done and every task has returned
```

- `Run` calls `t.Run` once at once, then again each time the wait after the previous call ends.
  Calls never overlap.
- An error or a panic in one call is logged with `Name` and counted as a failure. The next call is
  still scheduled.
- When `ctx` ends, the call in progress sees its context cancelled, and nothing more is scheduled.
  `Run` returns after that call returns.

### [CT-6] Startup order

Kind: invariant · Anchor: null

`app/backend/cmd/armadarr` loads the configuration, opens the pool, runs `Migrate`, builds domains and
features, starts their tasks, then starts the HTTP server. A migration failure exits the process
before the server listens. On `SIGINT` or `SIGTERM`, the server shuts down within 30 s, the tasks
stop, and then the pool closes.

### [CT-7] API contract

Kind: boundary · Anchor: `proto/armadarr/v1/health.proto`, `buf.gen.yaml`

- Services live in `proto/armadarr/v1/` and pass `buf lint` with the `STANDARD` rules.
- `buf generate` writes Go messages and Connect handlers to `app/backend/internal/gen` and a TypeScript client
  to `app/frontend/src/gen`. Generated code is committed, and CI fails when regenerating changes it.
- The server mounts every Connect handler under `/api`. The browser's transport uses the base URL
  `/api`.
- Handlers report failures with Connect codes: `InvalidArgument`, `NotFound`, `AlreadyExists`,
  `Unavailable` and `Internal`.

### [CT-8] Client build and serving

Kind: api · Anchor: `app/backend/internal/server/server.go#Handler`, `app/frontend/embed.go#Client`

```go
// app/backend/internal/server/server.go
func Handler(client fs.FS) http.Handler
```

- `/api/` routes to the Connect handlers. A feature's handler is added here when the feature lands
  (`[KD-6]`). Any other path serves the file of that name from
  `client`, `/` serves `index.html`, and a directory or a missing file answers 404.
- `pnpm build`, run in `app/frontend`, writes the client to `app/frontend/dist/client`. A binary built before it serves no client
  and logs a warning at startup.
- In development, `pnpm dev` serves the client with hot reload and proxies `/api` to the Go server
  on port 3000.

## Acceptance

- `[VC-1]` Given the test cluster and a domain with a unique name column, its Postgres store
  inserts a value and reads back the same value. Inserting the name a second time returns the
  domain's conflict error, and `errors.As` finds no pgx error in it. — demonstrates `[SO-1]`
- `[VC-2]` Given a store method that writes two rows and fails on the second, neither row exists
  afterwards. — demonstrates `[SO-2]`
- `[VC-3]` Given an empty database, two `Migrate` calls started together record each migration
  once. Given the application started on an empty database, the health check answers only after
  every migration is recorded. — demonstrates `[SO-3]`
- `[VC-4]` Under `testing/synctest`, a task with `Every: 10s` whose first call returns an error,
  whose second call panics and whose later calls succeed is called at 0 s, 10 s and 20 s.
  Cancelling its context at 25 s makes `Run` return with three calls recorded. — demonstrates
  `[SO-4]`
- `[VC-5]` `nix flake check` evaluates a NixOS configuration with `services.armadarr.postgres` and
  `secrets.postgresPasswordFile` set, and the unit's environment contains `POSTGRES_HOST` and
  `POSTGRES_PASSWORD_FILE`. — demonstrates `[SO-5]`
- `[VC-6]` A Go test calls `HealthService.Check` through the generated Go client over HTTP and
  gets `STATUS_OK`. A client test renders the app over a router transport built from the generated
  `HealthService` and shows the returned status, and shows the server as unreachable when the call
  fails. — demonstrates `[SO-6]`
- `[VC-7]` Given an in-memory client with `index.html` and `assets/`, the server answers `/` with
  the client page and `/assets/` with 404. — demonstrates `[SO-7]`

## Caveats

- `[C-1]` The generated TypeScript client has no compile-time list of the errors each RPC can
  return. Callers branch on the Connect code.
- `[C-2]` A second database needs a store implementation per domain and migrations in its own
  dialect. `[G-2]` keeps callers unchanged, not the SQL.
- `[C-3]` The dev shell does not provide `postgresql` yet. `[KD-8]` needs it for `initdb` and
  `pg_ctl`.
- `[C-4]` `flake.nix` pins no dependency hash. Go modules are committed in `vendor/`, which
  `go mod vendor` writes and Renovate updates. `nix/pnpm-lock.nix` fetches each client tarball with
  the integrity hash from `app/frontend/pnpm-lock.yaml`. Its YAML parser only reads the subset pnpm
  writes, so a lockfile format change can break evaluation.
- `[C-5]` Autoscan's speech detection uses onnxruntime, which needs cgo in Go. Porting it would end
  the `CGO_ENABLED=0` static build. Its spec decides.
- `[C-6]` The tests in `app/backend/internal/server/server_test.go`, `app/backend/internal/config/config_test.go` and
  `app/frontend/src/app.test.ts` cover the current health check and client serving, and stay as they are.
