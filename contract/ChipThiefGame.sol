// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
  ICasinoGameV2,
  SessionContext,
  StepResult,
  SessionPhase
} from "./ICasinoGameV2.sol";

/// @title Chip Thief — a goose robs a casino floor, one scripted run per bet.
/// @notice Mirrors prototypes/chip-thief.html's `RUN` paytable and `drawOutcome()`
///         exactly (same lam/mu/tables, same declared 96.0% RTP). This is an
///         "instant" game (ICasinoGameV2 §2.3): onSessionStart requests
///         randomness, onRandomness settles in one step, no player actions.
///
/// Randomness expansion: the facet hands us exactly one bytes32 VRF word, but
/// the client-side model rolls up to ~44 independent values per run (per-chip
/// land/value, per-multiplier land/tier, per-staff land/tier, leap survival,
/// gauntlet survival). Each draw reads the top 64 bits of
/// keccak256(randomness, idx) for a fresh idx — this is a direct comparison
/// against a 2^64-domain threshold, not a narrow-domain modulo (unlike the
/// classic "byte % 6" case in RANDOMNESS_DICE.md), so no rejection sampling
/// is needed: the bias from 2^64 not dividing evenly into a WAD probability
/// is below 2^-46 relative, undetectable at any stake size.
///
/// Leap-catch simplification: the client rolls one independent Bernoulli(LAM)
/// trial per landed chip/multiplier and busts if ANY succeeds. Whether at
/// least one of K independent trials succeeds doesn't depend on their order,
/// so this contract collapses that into a single draw against (1-LAM)^K —
/// bit-identical distribution, far less gas.
///
/// Payout cap: the client math's absolute combinatorial ceiling is
/// astronomically unlikely (~1,650x wager) but was never designed to be an
/// honest on-chain risk figure. A 30M-run simulation of the exact paytable
/// never produced a payout above 250x; this contract hard-caps settlement at
/// 300x wager. That cap is unreachable in practice (P < ~3e-8 per the sim)
/// and moves the declared 96.0% RTP by nothing at reportable precision — see
/// the repo's payout_tail_sim.js analysis.
contract ChipThiefGame is ICasinoGameV2 {
  uint256 internal constant WAD = 1e18;
  uint256 internal constant TWO64 = 18446744073709551616; // 2^64

  // ---- paytable constants, mirroring prototypes/chip-thief.html RUN ----
  uint256 internal constant CHIP_N = 15;
  uint256 internal constant MULT_N = 3;
  uint256 internal constant STEAL_N = 3;
  uint256 internal constant LAM_WAD = 22e15; // 0.022 per-leap catch chance
  // MU (0.07 gauntlet chance) is folded directly into GAUNTLET_SURV_THRESH_64.

  // RTP/rawEV(RUN) solved once offline so declared RTP == 96.0% exactly;
  // see docs/README or payout_tail_sim.js for the derivation.
  uint256 internal constant SCALE_WAD = 175617425823751168;

  uint256 internal constant CAP_MULTIPLIER = 300; // hard on-chain payout ceiling, x wager

  // ---- 64-bit thresholds: draw succeeds iff top64(hash) < THRESH ----
  uint64 internal constant CHIP_GOT_THRESH_64 = 9223372036854775808; // 0.50
  uint64 internal constant MULT_GOT_THRESH_64 = 4058283696216101355; // 0.22
  uint64 internal constant STAFF_GOT_THRESH_64 = 2767011611056432742; // 0.15
  uint64 internal constant GAUNTLET_SURV_THRESH_64 = 17155471988549883002; // 0.93 (survive)

  // Chip value tiers (already scaled by the client's chips.s=0.20, WAD) with
  // cumulative selection thresholds; weights 4000/2900/1800/850/370/80 bps.
  uint64 internal constant CHIP_CUM_0 = 7378697629483820646; // 0.40
  uint64 internal constant CHIP_CUM_1 = 12728253410859590615; // 0.69
  uint64 internal constant CHIP_CUM_2 = 16048667344127309905; // 0.87
  uint64 internal constant CHIP_CUM_3 = 17616640590392621793; // 0.955
  uint64 internal constant CHIP_CUM_4 = 18299170121119875203; // 0.992

  // Multiplier tiers m=2,3,5; weights 5000/3500/1500 bps.
  uint64 internal constant MULT_CUM_0 = 9223372036854775808; // 0.50
  uint64 internal constant MULT_CUM_1 = 15679732462653118873; // 0.85

  // Staff contact cut f=0.20,0.30,0.40 (WAD); weights 4500/3500/2000 bps.
  uint64 internal constant STAFF_CUM_0 = 8301034833169298227; // 0.45
  uint64 internal constant STAFF_CUM_1 = 14757395258967641292; // 0.80

  error ChipThiefGame__NoPlayerAction();

  // ---------------------------------------------------------------------
  // ICasinoGameV2
  // ---------------------------------------------------------------------

  function quoteCaps(
    uint256 wager,
    bytes calldata /* gameData */
  ) external pure returns (uint256 maxEscrowStake, uint256 maxReservedProfit) {
    maxEscrowStake = wager;
    maxReservedProfit = wager * (CAP_MULTIPLIER - 1);
  }

  function quoteRiskParams(
    uint256 wager,
    bytes calldata /* gameData */
  )
    external
    pure
    returns (
      uint256 maxPayout,
      uint256 probabilityWad,
      uint256 expectedPayout,
      uint256 bodyVarianceScaled
    )
  {
    maxPayout = wager * CAP_MULTIPLIER;
    // Conservative proxy for the top tier: the empirically-measured
    // P(payout >= 200x) ~= 2e-7 (30M-run sim), used instead of the unmeasurably
    // small P(payout >= 300x) since overstating tail risk is the safe
    // direction for vault solvency.
    probabilityWad = 2e11; // 2e-7 * 1e18
    expectedPayout = (wager * 96) / 100; // 96.0% RTP
    // sigma_body ~= 1.9556x per unit wager, empirically stable across every
    // tail-cut threshold tested; rounded up slightly (1.96x) for margin.
    uint256 bodySigmaWad = 1960000000000000000; // 1.96e18
    uint256 bodySigma = (wager * bodySigmaWad) / WAD;
    bodyVarianceScaled = bodySigma * bodySigma * WAD;
  }

  function onSessionStart(
    SessionContext calldata ctx
  ) external pure returns (StepResult memory r) {
    r.newGameState = "";
    r.escrowDelta = 0;
    r.reservedProfitDelta = int256(ctx.wagerBase * (CAP_MULTIPLIER - 1));
    r.nextPhase = SessionPhase.WAITING_RANDOMNESS;
    r.requestRandomnessNow = true;
    r.payout = 0;
  }

  function onPlayerAction(
    SessionContext calldata /* ctx */,
    bytes calldata /* actionData */
  ) external pure returns (StepResult memory) {
    revert ChipThiefGame__NoPlayerAction();
  }

  function onRandomness(
    SessionContext calldata ctx,
    bytes32 randomness
  ) external pure returns (StepResult memory r) {
    uint256 payout = _computePayout(ctx.wagerBase, randomness);
    r.newGameState = abi.encode(randomness, payout);
    r.escrowDelta = 0;
    // Don't release the reserve on the settling step (CONTRACT_CONSTRAINTS.md
    // "Payout cap") — _finalizeSession releases it itself.
    r.reservedProfitDelta = 0;
    r.nextPhase = SessionPhase.SETTLED;
    r.requestRandomnessNow = false;
    r.payout = payout;
  }

  function quoteForfeitPayout(
    SessionContext calldata /* ctx */
  ) external pure returns (uint256) {
    // Instant game: sessions never sit in WAITING_PLAYER_ACTION, so there is
    // never a cashable mid-round state.
    return 0;
  }

  // ---------------------------------------------------------------------
  // internal
  // ---------------------------------------------------------------------

  function _computePayout(uint256 wager, bytes32 randomness) internal pure returns (uint256) {
    uint256 idx = 0;
    uint256 landed = 0;
    uint256 chipSumWad = 0;
    uint256 multProdWad = WAD;

    for (uint256 i = 0; i < CHIP_N; i++) {
      if (_draw64(randomness, idx++) < CHIP_GOT_THRESH_64) {
        landed++;
        chipSumWad += _chipTierValueWad(_draw64(randomness, idx++));
      }
    }
    for (uint256 i = 0; i < MULT_N; i++) {
      if (_draw64(randomness, idx++) < MULT_GOT_THRESH_64) {
        landed++;
        multProdWad *= _multTierValue(_draw64(randomness, idx++));
      }
    }
    uint256 staffProdWad = WAD;
    for (uint256 i = 0; i < STEAL_N; i++) {
      if (_draw64(randomness, idx++) < STAFF_GOT_THRESH_64) {
        uint256 fWad = _staffTierFWad(_draw64(randomness, idx++));
        staffProdWad = (staffProdWad * (WAD - fWad)) / WAD;
      }
    }

    // Collapse `landed` independent Bernoulli(LAM) leap trials into one
    // (1-LAM)^landed survival draw (see contract-level docs above).
    uint256 survivalWad = WAD;
    for (uint256 i = 0; i < landed; i++) {
      survivalWad = (survivalWad * (WAD - LAM_WAD)) / WAD;
    }
    // survivalWad <= 1e18, TWO64 ~= 1.8e19 -> product ~= 1.8e37, safe.
    uint256 survive64 = (survivalWad * TWO64) / WAD;
    if (_draw64(randomness, idx++) >= survive64) return 0; // caught mid-run
    if (_draw64(randomness, idx++) >= GAUNTLET_SURV_THRESH_64) return 0; // caught at the door

    uint256 multiplierWad = (SCALE_WAD * chipSumWad) / WAD;
    multiplierWad = (multiplierWad * multProdWad) / WAD;
    multiplierWad = (multiplierWad * staffProdWad) / WAD;

    uint256 payout = (wager * multiplierWad) / WAD;
    uint256 cap = wager * CAP_MULTIPLIER;
    return payout > cap ? cap : payout;
  }

  function _draw64(bytes32 randomness, uint256 idx) internal pure returns (uint64) {
    return uint64(uint256(keccak256(abi.encodePacked(randomness, idx))) >> 192);
  }

  function _chipTierValueWad(uint64 roll) internal pure returns (uint256) {
    if (roll < CHIP_CUM_0) return 1e17; // 0.5 * 0.20
    if (roll < CHIP_CUM_1) return 2e17; // 1.0 * 0.20
    if (roll < CHIP_CUM_2) return 5e17; // 2.5 * 0.20
    if (roll < CHIP_CUM_3) return 1e18; // 5.0 * 0.20
    if (roll < CHIP_CUM_4) return 24e17; // 12.0 * 0.20
    return 5e18; // 25.0 * 0.20 (jackpot)
  }

  function _multTierValue(uint64 roll) internal pure returns (uint256) {
    if (roll < MULT_CUM_0) return 2;
    if (roll < MULT_CUM_1) return 3;
    return 5;
  }

  function _staffTierFWad(uint64 roll) internal pure returns (uint256) {
    if (roll < STAFF_CUM_0) return 2e17; // 0.20 cut, cleaner
    if (roll < STAFF_CUM_1) return 3e17; // 0.30 cut, security
    return 4e17; // 0.40 cut, pit boss
  }
}
