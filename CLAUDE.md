# Chain Jam Vol. 1 — project context

Handoff notes for a fresh session. Read this before touching anything; a lot of
what looks like an obvious improvement below has already been tried and rejected
for a stated reason.

## The jam

Build an original casino game on the free Chain casino SDK. Site: `jam.chain.wtf`,
SDK: `sdk.chain.wtf/casino`. Prizes 1,000 USDC (500/350/150) plus **25% lifetime
revenue share** on any entry integrated into chain.wtf, winner or not — the revenue
share is the real prize, so bets-per-session matters as much as placing.

**Deadline: extended to ~27 September 2026** (originally 20 September 23:59 UTC;
user confirmed the extension in session on 2026-09-21). Mention it once if
relevant; the user has explicitly asked not to have it drive every answer.

### Eligibility — pass/fail gates, not scoring
An entry is eligible only when it:
- Implements the Chain casino SDK exactly (**contract, bridge, manifest**)
- Runs correctly in the local simulator and loads near-instantly
- Has theoretical **RTP between 93–98%**, declared math matching the actual paytable
- Is recognisably a casino game and a novel concept — **no blackjack or classics,
  no plinko / dice / limbo / crash clones, no copies**
- Runs standalone as a playable demo outside the chain.wtf iframe
- Carries the jam widget and was submitted through jam.chain.wtf with source access

### Judging — four unweighted criteria
Novelty · Fun (still playing after 10 hours?) · Simplicity (no manual needed) ·
Visual & sound ("does it feel like a real game? No AI slop").

AI-generated code and assets are explicitly allowed.

## Repo

- `github.com/ketutezraugm/chain-jam-vol-1` — **private**, branch `main`
- Remote is **HTTPS** (SSH failed host-key verification; `gh auth setup-git` is configured)
- `gh` CLI is at `C:\Program Files\GitHub CLI\gh.exe` — **not on PATH**, call it by full path
- Authenticated as `ketutezraugm`
- Local git identity is `AkuTampanTay <ezradarkwing@gmail.com>`, which does **not**
  match the GitHub account, so commits won't link to the profile
- Flip public before submitting: `gh repo edit --visibility public`

## Layout

```
prototypes/chip-thief.html        the game — single HTML file, no build step
prototypes/game.manifest.json     Chain casino SDK manifest
prototypes/vendor/                vendored penpal + keccak256, same-origin, no CDN
contract/ChipThiefGame.sol        on-chain game contract (ICasinoGameV2)
contract/ICasinoGameV2.sol        vendored copy of the SDK's canonical interface
casino-sdk/                       local SDK dev/test stack — gitignored, not part of
                                   the submission; re-download from sdk.chain.wtf if
                                   missing (see "SDK integration" below)
README.md                         written for judges/outside readers
```

The other five prototypes (`insider.html`, `closing-time.html`, `underwriter.html`,
`smuggler.html`, `ghost-auction.html`) and the `Asset/` Claude Design export were
deleted on 2026-09-21 once Chip Thief was confirmed as the sole entry — the user
still has the source Claude Design project if any of that is ever needed again.
Don't re-create references to them.

---

# Chip Thief — current state

Single-file canvas game. Art direction is **"CAM 04"**: the entire game is framed
as casino CCTV footage.

## Core loop
One button. Stake, release the goose, watch a ~10s run down the casino floor toward
a fire exit 800m away. It grabs chips, gets tackled by staff, and either makes the
door or gets detained. No decisions during the run.

## Maths — exact, do not break this
RTP **96.0%**, bust rate **22.4%**. Everything is closed form and verified against
200k simulated runs in the self-check panel.

```
chips = n·p·(1−λ)·v̄·(1−pλ)^(n−1)
mults = (1−q + q(1−λ)·m̄)^k
staff = (1−s·f̄)^j
EV    = chips · mults · staff · (1−μ)
```

- `λ = 0.022` — per-leap chance the pursuer catches you. Every chip you reach for is
  another roll, so **greed is what gets you caught**.
- `μ = 0.07` — final-approach gauntlet, a flat hazard in the last 520px before the door.
- Getting caught forfeits the **entire haul** (payout 0).
- Survival is shared across all leaps, but the indicators stay independent, which is
  why it still factorises exactly.

`RUN.scale` is solved from `RTP/rawEV(RUN)` at load — if you change any table, the
scalar re-solves and RTP holds automatically. Verify with the self-check panel.

## Architecture rule that cannot change
**The outcome is drawn from the seed first; the animation replays a decided result.**
The flight path is generated *after* the rolls, to pass through whatever was actually
won. This is the only way it works against an on-chain VRF, and it's how real slot
reels work. Never compute a result from animation state.

## Decisions already made — with reasons

**Bust is tied to an action, never to elapsed time.** No climbing multiplier, no
cash-out button, no memoryless per-second tick. This is deliberate and load-bearing:
it is what keeps the game clear of the banned crash-clone pattern while still having
real jeopardy. **Do not add a cash-out or a time-based multiplier** — either one makes
the entry ineligible.

**One speed only (TROT, 10s, ~8 leaps).** Four selectable speeds existed and were
removed. BERSERK (5.2s, ~2.9 leaps) was unreadable — pickups and staff resolved faster
than the telegraph system could show them, which kills excitement rather than raising
it. Simplicity is 25% of the score and a first-time judge had no basis to choose a mode.

**Session RTP is off the HUD**, in the self-check panel instead. Over a handful of runs
it is pure noise; showing a player "58%" tells them they're losing, and a judge seeing
187% or 60% will doubt the maths. HUD shows cumulative RECOVERED instead.

**The 93–98% RTP band legalises real skill.** Used in the now-deleted `insider.html`
and `underwriter.html` prototypes, where sloppy play returned ~93.5% and sharp play
~97.8%. Chip Thief has zero decisions, so its declared RTP holds for every player
with no caveat.

**Art direction is Cam 04 surveillance, not neon.** A "NEON HEIST" asset sheet exists
in `Asset/Chip Thief Assets.dc.html` and was implemented then replaced. Reasons: the
magenta/cyan/yellow-on-purple palette is the default of every crypto game (bad for
Novelty and for "no AI slop"), it fought the comedy (neon is *cool*, the joke is a
goose), and the 0.5 chip at `#ff2d87` was invisible against the `#c11d5e` carpet.
Surveillance framing also *explains the architecture* — CCTV means you're watching
something that already happened, which is literally how the VRF works.

**Palette rule: the goose and the chips are the only warm objects in frame.** The room
is desaturated green-grey. This is what makes the eye track the subject with no effort;
don't add colour to the environment.

**Copy is deadpan incident-report language.** "CONTAINMENT FAILED", "SUBJECT LEFT THE
BUILDING", "ASSET RECOVERY: 0.00x". The system never acknowledges what it's reporting.
The gap between the flat language and the chaos on screen is the joke — no exclamation
marks, no wordplay, no winking.

## Dopamine work already done
Excitement comes from presentation, not variance — cranking variance just makes players
bust faster and the RTP display swing. These all raise perceived tension at identical EV:

- **Near-miss reach** — missed chips generate a partial leap so the goose visibly
  stretches and comes up short, with a beak-snap. Strongest single lever.
- **The pursuer** — a staff member permanently in frame behind you; the gap closes on
  every leap and drifts back when running level. Makes greed *visible*.
- **Threat-last staging** — one staff member is always dragged to within ~600–880px of
  the exit, so the closing seconds always put the full haul at risk. Costs nothing
  mathematically (the `got` roll happens before the reposition).
- **Time dilation** — eases to 0.42× when a jackpot, plaque, live multiplier or a
  connecting staff member is within 230px ahead.
- **Clustered pickups** — 4–6 pockets rather than an even sprinkle, so runs have quiet
  stretches then a flurry (and bunched leaps collapse the gap fast).
- **Staff telegraphed from 850px** plus edge-of-frame markers for threats off camera.
  Radio squelch fires ~260px before every contact as the only audio warning.
- **FINAL APPROACH banner** pulsing as you enter the gauntlet zone.

## Animation notes
The goose's legs are **drawn procedurally each frame**, not baked into the SVG. Feet
plant on the floor and slide back during stance, lift and reach forward during swing.
This was a real bug fix: trailing baked-in legs read as *flying* no matter what the
body did. Shelf heights are 440/384/316 against a floor at 520 and an approach of
`70 + lift×0.30`, so a grab is a ~200px hop, not a 600px glide.

Goose poses: `idle`, `sprint`, `beakFull`, `tackled`, `escape`. `sprint` and `beakFull`
carry `legs:true` and omit leg ops.

## Layout
Full-viewport grid, feed locked to **16:9** inside a centering stage capped at
`(100vh − 128px) × 16/9`, with a 268px system sidebar. World *height* is fixed at 620
and visible *width* follows the aspect ratio. Getting this wrong doesn't just overflow —
a too-tall feed **zooms in** and shows less floor.

---

# Eligibility checklist — status

All of it is pass/fail.

- [x] **SDK integration** — contract, bridge, manifest. Done and verified live
      against the local simulator (not just written — see below).
- [x] **Runs in the local simulator** — confirmed: opened a real session against
      the deployed contract through `?game=…&gameAddress=…`, watched it settle,
      balance updated correctly, no console errors from our code.
- [x] **Jam widget** embedded — `<script async src="https://jam.chain.wtf/widget.js">`
      in `chip-thief.html`'s `<head>`. Zero config (no game ID — it reports
      `location.pathname` and self-identifies from the submitted Game URL). It
      no-ops when embedded in an iframe (`window.top !== window.self`), so it
      only pings/heartbeats from the standalone page, never from inside
      chain.wtf's own iframe. Renders a small fixed bottom-right badge —
      confirmed by screenshot it doesn't overlap the RELEASE button or sidebar.
- [ ] **Hosted on own domain** — standalone mode works (confirmed in a real
      browser), but it isn't deployed anywhere yet; still file: local only.
- [ ] **Repo public** with source access — still private.
- [ ] **Submitted** via jam.chain.wtf — not started.
- [ ] Self-host the JetBrains Mono woff2 — still loading from the Google Fonts
      CDN (`prototypes/chip-thief.html` `<head>`); breaks the offline property.

## SDK integration — what exists and where

- `contract/ChipThiefGame.sol` (+ vendored `contract/ICasinoGameV2.sol`) —
  implements `ICasinoGameV2` as an instant game. Every client-side
  `Math.random()` roll (chip land/value, multiplier land/tier, staff
  land/tier, leap-catch, gauntlet) is reproduced on-chain via
  `keccak256(randomness, idx)` threshold draws — same lam/mu/tables/RTP as
  `RUN` in chip-thief.html, nothing about the declared paytable changed.
  Payout is hard-capped at **300× wager** (the real combinatorial ceiling is
  ~1,650× but is astronomically unlikely — a 30M-run sim never exceeded 250×;
  capping at 300× doesn't move the declared 96.0% RTP at reportable
  precision). `probabilityWad`/`bodyVarianceScaled` for the SDK's heavy-tail
  reserve model are set from that same simulation, biased conservative (safe
  direction for vault solvency). Verified against **300,000 live on-chain
  `onRandomness` calls**: 95.87% RTP / 22.31% bust vs. declared 96.0% / 22.4%
  — within statistical noise for a heavy-tailed distribution at that N.
- **Guest bridge**: `chip-thief.html`'s `<script>` is now `type="module"` and
  talks to the host via a hand-vendored `connectGameToHost` (mirrors
  `@chain/casino-sdk/guest` exactly). Zero new *build-time* deps — `penpal`
  and `@noble/hashes`' keccak are vendored as static files in
  `prototypes/vendor/` (same-origin, no runtime CDN call — same reasoning as
  the "self-host the font" item above, just not yet applied to the font
  itself). The page still runs standalone with zero changes to that path:
  outside an iframe `connection.promise` never resolves (documented SDK
  behavior) and the original local-`Math.random()` demo loop is what runs.
  Inside the iframe, `chainOutcomeFromRandomness()` in the page replays the
  contract's exact draw sequence from the session's on-chain VRF word — the
  animation is never a locally-rolled guess, it's the verified-identical
  reconstruction of what the contract already paid. Confirmed with **zero**
  `local replay disagreed with the chain payout` warnings across every live
  test run.
- `prototypes/game.manifest.json` — instant-game shape (same as coinflip's:
  `full-iframe`, `openSession` only), validated against the SDK's own
  `validateCasinoGameManifest`.
- Local dev/test stack lives in `casino-sdk/` at the repo root — the
  unzipped SDK package (simulator, VRF node, docs, coinflip example),
  gitignored, **not part of the submission**. Re-download from
  `sdk.chain.wtf/sdk/casino-sdk.zip` if missing. `npm install && npm start`
  from there brings up chain+VRF+simulator(:3300)+coinflip(:3100); the
  local-node watcher auto-compiles/deploys anything dropped into
  `casino-sdk/simulator/contracts/` — that's where the canonical
  `contract/ChipThiefGame.sol` gets copied for testing (copy again after any
  edit, the two aren't symlinked).
- To test chip-thief.html against the simulator: serve `prototypes/` with a
  **CORS-enabled** static server (plain `python -m http.server` fails — no
  `Access-Control-Allow-Origin` header, and the simulator fetches
  `game.manifest.json` cross-origin), then open
  `http://localhost:3300/?game=http://localhost:<port>/chip-thief.html&gameAddress=<ChipThiefGame address from casino-sdk/simulator/local-node/deployed.json>`.
  Forgetting `gameAddress` silently reuses whatever contract the simulator
  had loaded before (bit me once — it tried to open a Chip Thief session
  against CoinflipGame and reverted).

## Known gaps
- Plaque face value reads "500" but is worth 12x, while the jackpot chip reads "25" and
  is worth 25x — inconsistent if a judge looks twice.

## Rejected — don't re-propose
- **Cash-out / climbing multiplier** — makes the entry ineligible.
- **Slider-driven bets** — the decision is identical every round; set once and spam.
  Replaced with dealt choices (Insider/Underwriter) or no choice at all (Chip Thief).
- **Fake agency** — choices that don't affect anything. Players smell it and it fails
  "fun after 10 hours". Real agency inside the 93–98% band is the better trick.
- **Fracture / Net concepts** — required elaborate mouse work *every round*, which is
  fatiguing and suppresses bet count.

## Working style
The user wants brutal honesty over agreeableness, especially on design. They have
pushed back on: letting the deadline dominate answers, over-hedging, and shipping
things that look finished but aren't fun. Flag real problems directly, then build.
