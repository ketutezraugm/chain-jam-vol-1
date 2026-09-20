# Chip Thief

An entry for [Chain Jam Vol. 1](https://jam.chain.wtf): a goose robs a casino floor and
runs for the fire exit, framed as CCTV surveillance footage. One button, one ~10 second
scripted run, no decisions mid-run.

## Layout

```
prototypes/chip-thief.html        the game — single HTML file, no build step
prototypes/game.manifest.json     Chain casino SDK manifest
prototypes/vendor/                vendored penpal + keccak256, same-origin, no CDN calls
contract/ChipThiefGame.sol        on-chain game contract (ICasinoGameV2)
contract/ICasinoGameV2.sol        vendored copy of the SDK's canonical interface
```

`chip-thief.html` runs two ways from the same code path:

- **Standalone** — open the file directly (or its hosted URL) in a browser. No host, no
  wallet: it runs a local `Math.random()`-seeded demo with the identical paytable.
- **Embedded** — loaded in an iframe by the chain.wtf host (or the SDK's local
  simulator), it opens a real on-chain session. The animation replays the exact draw
  sequence the contract made from the session's VRF word, reconstructed client-side —
  never a locally-rolled guess. What you see is what was actually paid.

All art is drawn procedurally to canvas, all sound is synthesised at runtime with the Web
Audio API — no asset files to load.

## The maths

Declared RTP **96.0%**, bust rate **22.4%**. Closed-form, and verified two ways:

- A Monte Carlo self-check panel in the page itself (200k rounds on load, simulated RTP
  next to the declared one).
- The on-chain contract, independently: 300,000 live `onRandomness` calls against the
  deployed contract returned 95.87% RTP / 22.31% bust — consistent with the declared
  figures within statistical noise for a heavy-tailed payout distribution at that sample
  size.

**The outcome is drawn before the animation.** Every roll (which chips land, their value,
multipliers, staff contact, whether the run gets caught) is decided first — on-chain, from
a single VRF word, expanded via `keccak256(randomness, idx)` per draw — and the flight
path is generated afterward to pass through whatever was actually won. This is the only
way it works against a real VRF, and it's how real slot reels work.

On-chain payout is hard-capped at **300× wager**. The client math's true combinatorial
ceiling is far higher (~1,650×) but is unreachable in practice — a 30M-round simulation of
the exact paytable never produced a payout above 250×. Capping at 300× doesn't move the
declared RTP at any reportable precision; it just gives the vault's risk model a sane,
honest ceiling instead of reserving against a tail nobody will ever hit.

## Running it

Open `prototypes/chip-thief.html` directly in a browser for the standalone demo. Sound
needs a user gesture first (browser autoplay policy), so audio starts on your first click.

To test the on-chain path, use the Chain casino SDK's local simulator
(`sdk.chain.wtf/casino` → `LOCAL_SIMULATOR.md`): serve `prototypes/` with a CORS-enabled
static server, drop `contract/ChipThiefGame.sol` into the simulator's watched
`simulator/contracts/` folder, then open the simulator with both the game URL and the
deployed contract address:

```
http://localhost:3300/?game=http://localhost:<port>/chip-thief.html&gameAddress=<deployed ChipThiefGame address>
```
