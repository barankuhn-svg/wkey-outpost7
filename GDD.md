# GDD — WKey Take-Home: Enemy Spawner Demo
*Version 1.0 — 29.04.2026*
*Developer: Baran (b3lit)*

---

## 0) Überblick

Eine technische Demo für das WKey Studios Bewerbungsverfahren.
Kein vollständiges Spiel — Ziel ist es die technische Kompetenz zu demonstrieren:
- Custom Replication System (minimales Network Recv)
- Saubere One-Script Hierarchy
- Mobile-kompatibles UI
- 9-Sprachen Lokalisierung
- Professionelle Design-Entscheidungen

---

## 1) Stack

- **Sprache:** Luau (strict mode)
- **Workflow:** Rojo + Cursor + Claude
- **VCS:** GitHub (public, incrementelle Commits)
- **Animationen:** Mixamo → R15 Rig
- **Enemies:** Roblox Toolbox Free Models (R15)
- **Lokalisierung:** ko, pt-BR, tr, de, en, jp, ru, fr, es

---

## 2) Szenen / Screens

### Screen 1 — Play Screen
- Hintergrund: Außenposten-Bild (PNG, dunkel, atmosphärisch)
- Spielname: **"OUTPOST-7"** (mittig, groß)
- Play Button (mittig unten)
- Lokalisierter Text auf Play Button
- Beim Klick → Fade Out → Screen 2

### Screen 2 — Game Screen
- Die eigentliche Demo
- Kein Ladescreen nötig

### Screen 3 — Death Screen
- Overlay über Game Screen
- "YOU DIED" Text (lokalisiert)
- Restart Button → Kill All wird ausgeführt → Spieler respawnt → zurück zu Screen 2

---

## 3) Map — Außenposten

**Plattform:**
- 50x50 Studs, anchored Part
- Material: Concrete oder SmoothPlastic
- Farbe: Dunkelgrau
- Position: Workspace, Y=0

**Dekoration (optional, wenn Zeit):**
- 2-3 Crates / Barrels aus Toolbox als Deko
- Kein Einfluss auf Gameplay
- Darf Pathfinding NICHT blockieren (Enemies pathfinden nicht, aber Collision mit Deko würde Bewegung stören)

**Spawn:**
- Spieler spawnt mittig auf der Plattform
- SpawnLocation auf der Plattform platziert

**Außerhalb der Plattform:**
- Leere Baseplate oder Void
- Spieler außerhalb der Plattform werden von Enemies ignoriert

---

## 4) Enemy System

### 4.1 Enemy Modell
- R15 Rig aus Roblox Toolbox (Free Models)
- Mehrere verschiedene Modelle gemischt (3-5 verschiedene)
- Random beim Spawn ausgewählt
- Zusätzlich: Random Color / Material / Size Variation per ID-Seed (deterministisch)

### 4.2 Deterministische Random Attributes
```
Seed = EnemyID × 99991 + 31337
RNG = Random.new(Seed)
→ Color, Material, Size werden aus dem Seed generiert
→ Server und alle Clients rufen dieselbe Funktion auf → identisches Ergebnis
→ Kein extra Netzwerk-Traffic für Attributes nötig
```

### 4.3 Animationen (Mixamo)
| State | Animation |
|-------|-----------|
| Idle / Wander | Idle Standing |
| Chase | Running |
| Attack | Punch / Melee Attack |

### 4.4 Enemy States
| State | Bedingung | Verhalten |
|-------|-----------|-----------|
| Wander | Kein Spieler auf Plattform | Bewegt sich random auf Plattform |
| Chase | Spieler auf Plattform in Range | Läuft auf nächsten Spieler zu |
| Attack | Spieler innerhalb 5 Studs | Spielt Attack Animation, dealt Schaden |

### 4.5 Enemy AI
- Kein Pathfinding (Vorgabe: nicht erforderlich)
- Direkte Bewegung auf Ziel zu (Vector3 lerp)
- Spieler außerhalb der Plattform werden ignoriert
- Closest Player Check: XZ-Distanz (flach, ohne Y)

### 4.6 Unique ID
- Jeder Enemy bekommt eine monoton steigende Integer ID (1, 2, 3...)
- ID ist konsistent auf Server und allen Clients
- BillboardGui über Enemy zeigt ID an
- ClickDetector: Klick → print auf Client + Server

---

## 5) Custom Replication System — KERN

### Warum Custom Replication?
Standard Roblox: Server bewegt Part → automatische Replikation → hoher Network Recv Overhead pro Part.
Custom: Server hält Enemies als reine Lua-Tabellen, kein Part im Workspace server-seitig.

### Architektur

**Server:**
```
enemies = {
  [1] = { id=1, pos=Vector3, lookDir=Vector3, state="chase" },
  [2] = { id=2, pos=Vector3, lookDir=Vector3, state="wander" },
  ...
}
```
- Alle 50ms (20Hz): Server packt ALLE Enemy-Positionen in EIN RemoteEvent
- Format: { {id, px, py, pz, lx, lz, stateCode}, ... }
- FireAllClients mit einem einzigen Call

**Client:**
```
registry = {
  [1] = { body=Part, targetCF=CFrame },
  ...
}
```
- Client empfängt Batch → updated targetCF pro Enemy
- RenderStepped: exponentieller Lerp → smooth movement
- alpha = 1 - exp(-LERP_SPEED × dt)

### RemoteEvents
| Event | Richtung | Payload |
|-------|----------|---------|
| EnemySpawn | Server → Client | id, pos, color, material, size |
| EnemyBatch | Server → Client | alle Positionen + States |
| EnemyDestroy | Server → Client | Liste von IDs |
| EnemyClicked | Client → Server | id |
| KillAll | Client → Server | - |
| UpdateSettings | Client → Server | spawnRate, maxEnemies |
| GetAllEnemies | Client → Server (RF) | Late-Join Snapshot |

---

## 6) Spieler

- Standard Roblox Character (R15)
- Spawnt mittig auf der Plattform
- HP: 100 (Roblox Standard Humanoid)
- Wenn HP = 0 → Death Screen
- Restart: Kill All → Character respawn → Game Screen

---

## 7) UI — Rechts mittig am Bildschirmrand

### Layout (Mobile First, relativ skaliert)
```
[Panel rechts mittig]
├── Spawn Rate Label
├── Spawn Rate Slider (0.1 – 10)
├── Spawn Rate Input (TextBox)
├── Max Enemies Label  
├── Max Enemies Slider (1 – 100)
├── Max Enemies Input (TextBox)
├── [Apply Button]
└── [KILL ALL Button] (rot)
```

### Mobile UIController
- Alle Größen via UDim2 relativ (kein fixer Pixelwert)
- Buttons minimum 44×44px (Apple HIG Standard)
- IgnoreGuiInset = true
- Touch-freundliche Slider

### Death Screen
- Semi-transparentes Overlay
- "YOU DIED" (lokalisiert, groß, mittig)
- [RESTART] Button (mittig unten, lokalisiert)

### Play Screen
- Fullscreen PNG Hintergrund
- Spielname "OUTPOST-7" (lokalisiert)
- [PLAY] Button (mittig unten, lokalisiert)

---

## 8) Lokalisierung

**Sprachen:** en, de, tr, ru, fr, es, pt-BR, ko, jp

**Keys:**
```
ui.play_button      → "PLAY" / "SPIELEN" / "OYNA" ...
ui.kill_all         → "KILL ALL" / "ALLE TÖTEN" ...
ui.spawn_rate       → "Spawn Rate" ...
ui.max_enemies      → "Max Enemies" ...
ui.apply            → "Apply" / "Übernehmen" ...
ui.you_died         → "YOU DIED" / "TOD" ...
ui.restart          → "RESTART" / "NEUSTART" ...
ui.enemy_id         → "ID: {id}"
ui.game_title       → "OUTPOST-7" (kein Übersetzen nötig)
```

---

## 9) Spawn System

- SpawnRate: Standard 1 Enemy/Sekunde (einstellbar via UI)
- MaxEnemies: Standard 20 (einstellbar via UI)
- Spawn Position: Random auf Plattform (XZ random, Y = Plattform Oberfläche + Offset)
- Wenn MaxEnemies erreicht → kein neuer Spawn bis ein Enemy stirbt

---

## 10) Config (Server, anpassbar via UI)

```lua
Config = {
    SPAWN_RATE    = 1,      -- enemies/sec
    MAX_ENEMIES   = 20,     -- hard cap
    CHASE_SPEED   = 12,     -- studs/sec
    WANDER_SPEED  = 4,      -- studs/sec
    ATTACK_RANGE  = 4,      -- studs
    ATTACK_DAMAGE = 10,     -- HP pro Hit
    ATTACK_CD     = 1,      -- Sekunden zwischen Hits
    WANDER_INTERVAL = 3.5,  -- Sekunden bis neues Wander-Ziel
    UPDATE_RATE   = 0.05,   -- 20Hz Batch
}
```

---

## 11) Dateistruktur (Rojo)

```
wkey-takehome/
├── default.project.json
├── README.md
└── src/
    ├── server/
    │   └── Main.server.luau        ← Gesamte Server-Logik
    ├── client/
    │   └── EnemyClient.client.luau ← Gesamte Client-Logik
    └── shared/
        └── Localization.luau       ← Lokalisierungs-Tabellen
```

---

## 12) One-Script Hierarchy

- **1 Server Script** → alles: Spawn, AI, Custom Replication, Remote Handling
- **1 LocalScript** → alles: Client Rendering, UI, Lerp, Lokalisierung
- **1 ModuleScript** → nur Lokalisierungs-Tabellen (shared)
- Keine weitere Aufteilung

---

## 13) Submission Text (Vorbereitung)

Nach Fertigstellung wird erklärt:
1. Custom Replication Architektur (warum kein server-seitiger Part)
2. Deterministische Attribute via ID-Seed
3. Exponentieller Lerp für smooth movement bei 20Hz
4. One-Script Hierarchy Entscheidung
5. Mobile-first UI
6. 9-Sprachen Lokalisierung als Bonus

---

## 14) Reihenfolge beim Bauen

1. Rojo Projekt + GitHub Repo aufsetzen (Commit #1)
2. Map: Platform + SpawnLocation (Commit #2)
3. Server: Main.server.luau — Spawn + AI + Batch (Commit #3)
4. Client: EnemyClient — Rendering + Lerp (Commit #4)
5. Mixamo Animationen einbauen (Commit #5)
6. UI: Play Screen + Game UI + Death Screen (Commit #6)
7. Lokalisierung (Commit #7)
8. Testing + Bugfix (Commit #8)
9. Roblox veröffentlichen + Submission
