# Submission Notes

## Custom Replication Approach

I implemented a table-driven server simulation with explicit network replication, instead of server-owned enemy instances.

- On the server (`Main.server.luau`), enemies are stored in a Lua table (`enemies`) with fields like `id`, `pos`, `lookDir`, `state`, timers, and wander target.
- The server sends:
  - `EnemySpawn` once per new enemy (id + deterministic visual attributes),
  - `EnemyBatch` at 20Hz (`UPDATE_RATE = 0.05`) with compact positional/state payloads,
  - `EnemyDestroy` for removals.
- On the client (`EnemyClient.client.luau`), enemies are rendered as local parts and tracked in a local registry with `body`, `targetCF`, and `state`.
- Client movement is smoothed in `RenderStepped` with exponential interpolation:
  - `alpha = 1 - exp(-18 * dt)`.

### Why this was chosen

- Keeps enemy movement authoritative on the server while minimizing default per-part replication overhead.
- Gives deterministic, smooth client visuals from low-frequency batched updates.
- Matches the required custom replication architecture.

## Deterministic Random Attributes

Enemy appearance is generated from ID-based deterministic RNG:

- Seed formula: `Random.new(id * 99991 + 31337)`.
- Attributes generated from fixed pools/ranges:
  - color from a 7-color pool,
  - material from a 5-material pool,
  - size from `[2.0, 4.0]`.
- Server computes these on spawn and in `GetAllEnemies` snapshots for late join.
- Because the seed depends only on enemy ID, attributes stay stable and consistent for all clients.

## One-Script Hierarchy Decision

The implementation uses one-script hierarchy in practice:

- `src/server/Main.server.luau`: all server logic (remotes, config, spawn, AI, replication, settings, respawn handling).
- `src/client/EnemyClient.client.luau`: all client logic (registry/rendering, interpolation, UI, localization usage, click behavior).
- `src/shared/Localization.luau`: shared localization table.

### Why

- For this scope, centralization keeps flow easy to reason about and fast to iterate.
- Avoids over-abstracting a small technical demo.

## Ideas Considered But Not Used

The current code intentionally avoids these alternatives:

- No Roblox default movement replication for enemies (server does not create replicated enemy parts).
- No pathfinding system (AI movement is direct steering + wander target logic).
- No multi-module feature split beyond the localization module.
- No server-side animation/state-machine framework beyond current state codes and movement/attack logic.

These were avoided to stay aligned with the required architecture and constraints.

## Extra Features Added Beyond Baseline Requirements

Implemented additions currently in code:

- **Play gating (`SetPlaying`)**
  - Enemy spawning/targeting only starts after the player presses Play.
- **Server-side respawn flow**
  - Restart sends a request and the server calls `LoadCharacter()` (no client-side respawn call).
- **Forced platform spawn placement**
  - Character is positioned to platform center on spawn, with velocities reset.
- **Start screen polish**
  - Fullscreen background image support.
  - Rainbow per-letter title rendering with stroke and shadow.
  - Pill-style Play button with gradient, stroke, and hover scale tween.
- **Enemy click popup UX**
  - Temporary 2-second local billboard ID popup on click.
- **Late-join recovery**
  - `GetAllEnemies` snapshot to reconstruct active enemies for new clients.
- **Settings clamping**
  - Spawn/max updates are clamped server-side (`0.1..10`, `1..100`).
