# Chain Jam Vol. 1 — prototypes

Concept prototypes for [Chain Jam Vol. 1](https://jam.chain.wtf), a game jam for original
casino games built on the Chain casino SDK.

Every file here is a **self-contained single HTML page**. No build step, no dependencies, no
network calls. Open one in a browser and it runs — including offline. All sound is synthesised
at runtime with the Web Audio API, and all art is drawn procedurally to canvas or CSS, so there
are no asset files to load.

These are **feel prototypes**, not jam submissions. They use local `Math.random()` rather than
the SDK's VRF, and none of them implement the contract/bridge/manifest yet.

## The prototypes

| File | Idea | Input | Shape |
|---|---|---|---|
| [`chip-thief.html`](prototypes/chip-thief.html) | A goose loose on a casino floor, robbing chip racks on its way to the fire exit | Pick a speed, press go | Continuous auto-run, no decisions |
| [`insider.html`](prototypes/insider.html) | Six deposit boxes, one holds the bonds — buy tips from unreliable sources before you open one | Buy up to 2 tips, pick a box | Deduction under an information market |
| [`closing-time.html`](prototypes/closing-time.html) | The last collection round of the night, walking a looping casino floor | One button | Markov walk over a 16-tile board |
| [`underwriter.html`](prototypes/underwriter.html) | Three insurance policies cross your desk; spot which premium is worth its risk | Click a policy | Dealt choice, mispriced options |
| [`smuggler.html`](prototypes/smuggler.html) | Five bags at the border — declare them, or hide them | Tap bags, then cross | Player-set volatility, flat EV |
| [`ghost-auction.html`](prototypes/ghost-auction.html) | Three sealed lots, each drawing a different crowd | Click a lot | Two random variables, spread payoff |

## Design constraints these were built against

The jam's rules shape all of them:

- **RTP must sit between 93% and 98%**, with declared math matching the actual paytable
- **No blackjack or other classics; no plinko / dice / limbo / crash clones; no copies**
- Must be recognisably a casino game, and a novel concept
- Must load near-instantly and run standalone outside the chain.wtf iframe

Two consequences worth knowing if you read the code:

**The outcome is drawn before the animation.** In `chip-thief.html` the run's result is decided
up front, and the flight path is then generated to pass through whatever was actually won. The
animation is a presentation layer over a decided result — the same way a slot machine's reels
work, and the only way this can work against an on-chain VRF.

**93–98% is a range, so real skill is legal.** `insider.html` and `underwriter.html` deal options
whose EVs differ slightly within that band. Sloppy play returns ~93.5%, sharp play ~97.8%. The
house edge never moves; the player's edge inside it is genuine.

## Verifying the maths

Every prototype has a **Math self-check** panel at the bottom of the page. It runs a Monte Carlo
simulation on load (100k–1M rounds, depending on the game) and prints the simulated RTP next to
the declared one, per strategy or per volatility setting.

Where a closed form exists it's stated and used as the source of truth, with the simulation only
confirming it. In `chip-thief.html`, payouts are order-independent by construction — chips sum,
multipliers scale the whole haul, staff take a fixed cut of the whole haul — so:

```
EV = (n · p · mean) × (1 − q + q·E[m])^k × (1 − s · E[f])^j
```

`closing-time.html` is the exception: its board is a 16-state Markov chain currently calibrated
by simulation rather than solved exactly. That would need doing properly before submission.

## Running them

Open any `.html` file in `prototypes/` directly in a browser. That's it.

Sound requires a user gesture first (browser autoplay policy), so audio starts on your first click.
