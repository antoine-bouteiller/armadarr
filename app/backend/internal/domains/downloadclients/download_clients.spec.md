---
title: Download Clients and qBittorrent Queue Poller
status: review
author: Antoine Bouteiller
date: 2026-11-27
module:
  - app/backend/internal/domains/downloadclients
  - app/backend/internal/integrations/qbittorrent
  - app/backend/internal/features/downloadclients
  - proto/armadarr/v1/download_clients.proto
  - app/backend/internal/database/migrations
related:
  - docs/project_foundation.spec.md
---

## Why

Armadarr has to know what its download client is doing: what is queued, downloading, stalled,
finished or broken. The deployment runs qBittorrent today, but the \*arr apps support several
clients, and Armadarr should be able to move to another one without touching the code that reads
the queue. Download clients are configured at runtime, as in Sonarr and Radarr, not through the
environment. Autoscan's queue cleanup, which removes stalled downloads, will move into Armadarr
later and will read the queue defined here.

- `[G-1]` Keep a live, normalized view of each configured download client's queue.
- `[G-2]` Add, change, enable, disable and remove download clients through the API, with the
  matching poller starting or stopping without a restart.
- `[G-3]` Isolate qBittorrent behind a driver interface, so another client is a new driver and
  nothing above the interface changes.
- `[G-4]` Expose the queue to the browser as a snapshot and as a stream of changes.
- `[NG-1]` Acting on downloads: removing, pausing, blocklisting or adding torrents.
- `[NG-2]` Stall detection and cleanup. A later spec adds it on top of `[CT-5]`.
- `[NG-3]` Drivers other than qBittorrent.
- `[NG-4]` qBittorrent API-key authentication.

## Design

- `[PI-1]` The queue is the client's truth: Armadarr stores no download state, only client
  settings. A restart rebuilds the queue from the clients.
- `[PI-2]` Drivers translate, the domain decides: a driver turns a client's API into `[CT-3]`
  items. Polling cadence, backoff, diffing and publishing belong to the domain and are the same for
  every driver.
- `[PI-3]` No silent gaps: a consumer of the change stream either sees every change or is told to
  start again from a snapshot.

| Decision                           | Choice                                                                                                                                                               | Rationale                                                                                                                                               |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[KD-1]` Driver interface          | A driver opens a session from stored settings, and `Session.Poll` returns the client's complete queue (`[CT-2]`).                                                    | Incremental protocols such as qBittorrent's `rid` stay inside the driver. A client without one returns a full list each time.                           |
| `[KD-2]` qBittorrent sync          | Poll `/api/v2/sync/maindata` with the last `rid` and merge the delta into the session's torrent map. Any failure resets `rid` to 0.                                  | One request returns only what changed. Resetting after a failure forces a full update, so a missed delta cannot leave stale torrents.                   |
| `[KD-3]` Status mapping            | qBittorrent states map to a closed status set with `UNKNOWN` as fallback (`[CT-4]`).                                                                                 | Consumers such as the future cleanup branch on Armadarr statuses, never on client strings. A new qBittorrent state decodes instead of failing the poll. |
| `[KD-4]` Cadence                   | One poller per enabled client, as a `task.Task` with `Every: 2s` and a backoff doubling from 2 s, capped at 60 s.                                                    | 2 s keeps the UI live. On localhost the cost is one small request per client.                                                                           |
| `[KD-5]` Poller lifetime           | `Queue` owns a `task.Group` keyed by client id. Create and update restart that client's poller; disable and delete stop it.                                          | Settings changes take effect at once, and cancelling the root context stops every poller (`docs/project_foundation.spec.md` `[KD-5]`).                  |
| `[KD-6]` Change delivery           | Each subscriber has a buffered channel of 256 events. A subscriber whose buffer is full receives `Resync` and is dropped. It subscribes before reading the snapshot. | Publishing never blocks on a slow reader, memory stays bounded, and the reader knows to start again.                                                    |
| `[KD-7]` Browser transport         | `DownloadQueueService.WatchQueue`, a Connect server stream whose first message is a snapshot.                                                                        | The browser gets the same generated, typed client as other RPCs. A reconnect starts from a snapshot.                                                    |
| `[KD-8]` Settings storage          | One `download_clients` row per client. Driver settings are a JSON document in a `text` column, decoded by the driver.                                                | Portable SQL (`docs/project_foundation.spec.md` `[G-2]`). Each driver owns its settings shape without a table per driver.                               |
| `[KD-9]` Typed settings in the API | Each driver's settings are their own message in a `oneof` (`[CT-6]`). The driver kind is the `oneof` case and cannot change on update.                               | The browser edits typed fields, not free-form JSON.                                                                                                     |
| `[KD-10]` Write-only password      | Responses carry `has_password`, never the password. An update without a password keeps the stored one.                                                               | The UI can edit a client without reading its secret back.                                                                                               |
| `[KD-11]` Forward compatibility    | Item ids are stable across polls and restarts (the torrent info-hash). `Session` is where removal will be added when cleanup lands.                                  | The cleanup needs to track each item over time and then remove it through the same driver.                                                              |

## Outcome

- `[SO-1]` A client added through the API is polled within one interval, and its queue appears in
  `GetQueue`. — demonstrated by `[VC-5]`
- `[SO-2]` The qBittorrent driver keeps a correct queue from incremental updates and recovers with
  a full update after any failure. — demonstrated by `[VC-1]`, `[VC-3]`
- `[SO-3]` Every qBittorrent state maps to one Armadarr status, and unknown states map to
  `UNKNOWN`. — demonstrated by `[VC-2]`
- `[SO-4]` An unreachable client shows as unreachable with the error, is retried with capped
  backoff, and returns to connected by itself. — demonstrated by `[VC-6]`
- `[SO-5]` `WatchQueue` starts with a snapshot, then carries only changed items, and never skips
  changes silently. — demonstrated by `[VC-7]`, `[VC-8]`
- `[SO-6]` Updating or deleting a client restarts or stops its poller without restarting
  Armadarr. — demonstrated by `[VC-5]`
- `[SO-7]` Client passwords never appear in API responses. — demonstrated by `[VC-4]`

## Contracts

### [CT-1] Client settings

Kind: schema · Anchor: null

```sql
-- app/backend/internal/database/migrations/00001_download_clients.sql
CREATE TABLE download_clients (
  id       uuid    PRIMARY KEY,  -- UUIDv7, generated by Armadarr
  name     text    NOT NULL UNIQUE,
  kind     text    NOT NULL,     -- a driver kind: 'qbittorrent'
  enabled  boolean NOT NULL,
  settings text    NOT NULL      -- JSON, decoded by the driver
);
```

```go
// app/backend/internal/domains/downloadclients/qbittorrent/settings.go
type Settings struct {
	URL      string `json:"url"`                // WebUI base URL
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
}
```

Without a username, the session sends no login, which matches qBittorrent's `LocalHostAuth =
false` on the current server.

### [CT-2] Driver interface

Kind: api · Anchor: null

```go
// app/backend/internal/domains/downloadclients/driver.go
type Kind string

const KindQbittorrent Kind = "qbittorrent"

type Driver interface {
	Kind() Kind
	// Open validates settings, the stored JSON, and returns a session. It does no I/O.
	Open(settings json.RawMessage) (Session, error)
}

// Session holds one client's connection state, such as a login cookie or a sync cursor.
type Session interface {
	// Poll returns the client's complete current queue. Calls never overlap.
	Poll(ctx context.Context) ([]Item, error)
}

type ErrorReason int

const (
	Unreachable ErrorReason = iota + 1
	Unauthorized
	InvalidResponse
)

type Error struct {
	Reason ErrorReason
	Err    error
}
```

`Poll` returns `*Error` for every failure. The vendor HTTP client lives in
`app/backend/internal/integrations/qbittorrent` and returns qBittorrent's own types. The driver in
`app/backend/internal/domains/downloadclients/qbittorrent` maps them to `Item`.

### [CT-3] Download item

Kind: type · Anchor: null

```go
// app/backend/internal/domains/downloadclients/item.go
type Status int // Queued, Downloading, Stalled, Paused, Checking, Completed, Failed, Unknown

type Item struct {
	ID             string    // stable per client: the torrent info-hash for qBittorrent
	Name           string
	Category       string    // "" when none
	Status         Status
	Message        string    // client-reported error, "" when none
	Progress       float64   // 0..1
	SizeBytes      int64
	RemainingBytes int64
	DownloadSpeed  int64     // bytes per second
	ETA            time.Duration // 0 when the client reports none or infinity
	ContentPath    string
	AddedAt        time.Time
}
```

`proto/armadarr/v1/download_clients.proto` mirrors it as `DownloadItem` with a
`DownloadStatus` enum whose values are prefixed `DOWNLOAD_STATUS_`.

### [CT-4] qBittorrent mapping

Kind: invariant · Anchor: null

| qBittorrent `state`                                                       | Status        |
| ------------------------------------------------------------------------- | ------------- |
| `downloading`, `forcedDL`, `metaDL`, `forcedMetaDL`                       | `Downloading` |
| `stalledDL`                                                               | `Stalled`     |
| `queuedDL`                                                                | `Queued`      |
| `pausedDL`, `stoppedDL`                                                   | `Paused`      |
| `checkingDL`, `checkingUP`, `checkingResumeData`, `allocating`, `moving`  | `Checking`    |
| `uploading`, `forcedUP`, `stalledUP`, `queuedUP`, `pausedUP`, `stoppedUP` | `Completed`   |
| `error`, `missingFiles`                                                   | `Failed`      |
| anything else                                                             | `Unknown`     |

| Item field       | qBittorrent field                                |
| ---------------- | ------------------------------------------------ |
| `ID`             | key of `torrents` in `maindata`                  |
| `Message`        | `error` when non-empty (WebAPI 2.17.0 and later) |
| `SizeBytes`      | `size`                                           |
| `RemainingBytes` | `amount_left`                                    |
| `DownloadSpeed`  | `dlspeed`                                        |
| `ETA`            | `eta` seconds, with `8640000` as 0               |
| `ContentPath`    | `content_path`                                   |
| `AddedAt`        | `added_on` (Unix seconds)                        |

Session protocol:

- Each session has its own `http.Client` with a cookie jar and a 10 s timeout.
- With a username, the session logs in at `POST /api/v2/auth/login` with `Referer` set to the base
  URL. Login succeeds when the response sets a cookie. The jar keeps it under the name the server
  chose, which is `SID` or `QBT_SID_<port>` depending on the version.
- A `403` on `maindata` triggers one new login and one retry. A second `403` fails the poll with
  `Unauthorized`.
- `full_update: true` replaces the torrent map. Otherwise the session merges each partial torrent
  into the map field by field and deletes `torrents_removed`.

### [CT-5] Queue service and events

Kind: api · Anchor: null

```go
// app/backend/internal/domains/downloadclients/queue.go
type Queue struct{ /* … */ }

func NewQueue(store Store, drivers []Driver) *Queue

// Run starts a poller for every enabled client and returns when ctx is done and every poller has stopped.
func (q *Queue) Run(ctx context.Context) error
func (q *Queue) Snapshot() []ClientQueue
// Subscribe returns the snapshot and the events after it. The channel closes after Resync or when ctx is done.
func (q *Queue) Subscribe(ctx context.Context) ([]ClientQueue, <-chan Event)
func (q *Queue) Start(client Client) // restarts a running poller
func (q *Queue) Stop(id uuid.UUID)

type ClientState struct {
	Status ConnectionStatus // Connecting, Connected, Unreachable
	Error  string
}

type ClientQueue struct {
	ClientID uuid.UUID
	State    ClientState
	Items    []Item
}

// Event is one of ItemsChanged, ClientStateChanged, ClientRemoved or Resync.
type Event interface{ isEvent() }

type ItemsChanged struct {
	ClientID uuid.UUID
	Upserted []Item
	Removed  []string
}
type ClientStateChanged struct {
	ClientID uuid.UUID
	State    ClientState
}
type ClientRemoved struct{ ClientID uuid.UUID }
type Resync struct{}
```

- `ItemsChanged` is published only when a poll differs from the previous one. `Upserted` holds
  only items with at least one changed field.
- When a client becomes unreachable, its last items stay in the snapshot until it is reachable
  again, disabled or deleted.

### [CT-6] API

Kind: api · Anchor: null

```proto
// proto/armadarr/v1/download_clients.proto
service DownloadClientService {
  rpc ListClients(ListClientsRequest) returns (ListClientsResponse); // NO_SIDE_EFFECTS
  rpc CreateClient(CreateClientRequest) returns (CreateClientResponse);
  rpc UpdateClient(UpdateClientRequest) returns (UpdateClientResponse);
  rpc DeleteClient(DeleteClientRequest) returns (DeleteClientResponse);
}

service DownloadQueueService {
  rpc GetQueue(GetQueueRequest) returns (GetQueueResponse); // NO_SIDE_EFFECTS
  rpc WatchQueue(WatchQueueRequest) returns (stream WatchQueueResponse);
}

message DownloadClient {
  string id = 1;
  string name = 2;
  bool enabled = 3;
  oneof settings {
    QbittorrentSettings qbittorrent = 10;
  }
}

message QbittorrentSettings {
  string url = 1;
  string username = 2;
  optional string password = 3; // write-only: never set in responses
  bool has_password = 4;        // read-only: ignored in requests
}

message WatchQueueResponse {
  oneof event {
    QueueSnapshot snapshot = 1;
    ItemsChanged items_changed = 2;
    ClientStateChanged client_state_changed = 3;
    ClientRemoved client_removed = 4;
    Resync resync = 5;
  }
}
```

| RPC            | Connect errors                                                                     |
| -------------- | ---------------------------------------------------------------------------------- |
| `CreateClient` | `InvalidArgument` for settings the driver rejects, `AlreadyExists` for a used name |
| `UpdateClient` | the same, plus `NotFound`, and `InvalidArgument` when the `oneof` case changes     |
| `DeleteClient` | `NotFound`                                                                         |

`WatchQueue` sends a `snapshot` first and ends after `resync`.

## Acceptance

- `[VC-1]` Given a stub qBittorrent that answers `rid=0` with a full update of torrents A and B,
  then `rid=1` with A's state changed to `stalledDL` and B in `torrents_removed`: the second `Poll`
  returns only A, with status `Stalled` and A's other fields unchanged, and the stub received
  `rid=0` then `rid=1`. — demonstrates `[SO-2]`
- `[VC-2]` For each row of the `[CT-4]` state table, plus `"someFutureState"`, a single-torrent
  full update produces the listed status. A torrent with `eta: 8640000` and `category: ""` yields
  `ETA` 0 and `Category` "". — demonstrates `[SO-3]`
- `[VC-3]` Given a stub that issues the cookie `QBT_SID_9999` at login and answers one `maindata`
  call with `403`: the session logs in again, retries with `QBT_SID_9999`, and the poll succeeds.
  When `403` repeats, the poll fails with `Unauthorized`. After any failed poll, the next request
  carries `rid=0`. — demonstrates `[SO-2]`
- `[VC-4]` Given a client created with a password, `ListClients` returns `has_password: true` and
  no password. An `UpdateClient` without a password followed by a forced login sends the original
  password to the stub. — demonstrates `[SO-7]`
- `[VC-5]` Through the generated Go client against the test database and a stub qBittorrent:
  `CreateClient`, and within 5 s `GetQueue` lists the stub's torrents. An `UpdateClient` with
  another URL moves polling to a second stub. A `DeleteClient` stops all requests to it and removes
  the client from `GetQueue`. A duplicate name returns `AlreadyExists`. — demonstrates `[SO-1]`,
  `[SO-6]`
- `[VC-6]` Under `testing/synctest`, with `Queue` over a test-registered driver whose `Poll` fails
  three times with the message `stub down` and then returns one item named `fake-item`: the client
  state is unreachable with `stub down`, retries happen at 2 s, 4 s and 8 s, and the state then
  becomes connected with `fake-item` in the snapshot. — demonstrates `[SO-4]`
- `[VC-7]` A `WatchQueue` stream receives `snapshot` first. When one of two items changes its
  progress, the next message is `items_changed` with exactly that item. A poll with no change
  publishes nothing. — demonstrates `[SO-5]`
- `[VC-8]` A `Subscribe` caller that reads nothing while 257 events are published receives `Resync`
  and then a closed channel. — demonstrates `[SO-5]`

## Caveats

- `[C-1]` qBittorrent before 5.0 reports `pausedDL` and `pausedUP`; 5.0 and later report
  `stoppedDL` and `stoppedUP`. `[CT-4]` maps both.
- `[C-2]` The future cleanup cannot reuse Autoscan's "five passes" threshold: passes here are 2 s
  apart, not 10 minutes. It has to count elapsed time per item id.
- `[C-3]` Polling never stops while a client is enabled, even with no browser connected, because
  in-process consumers read the same state.
- `[C-4]` The admin API has no authentication (`docs/project_foundation.spec.md` `[NG-1]`), so
  anyone who reaches it can change client URLs and credentials.
- `[C-5]` `WatchQueue` sends nothing while the queue is unchanged. A proxy with an idle timeout
  closes the stream, and the client reconnects and receives a new snapshot.

## Open Questions

- `[OQ-1]` Should client passwords be encrypted at rest, with a key from a secret file, or stored
  as plain text like Sonarr and Radarr do? — needs: `risk` · who can read the Postgres database
  and its backups, the NixOS secret-file setup
