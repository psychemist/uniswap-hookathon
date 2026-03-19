import { clamp } from "./format";

// Mirror the onchain model at a high level for visualization.
// All values are in millionths (Uniswap v4 fee units), where 1e6 == 100%.
const BASE_FEE = 3000; // 0.30%
const MIN_FEE = 100; // 0.01%
const MAX_FEE = 50000; // 5.00%

export function feeUnitsToBps(units: number) {
  // 1 bps == 0.01% == 100 units in 1e6 scale
  return units / 100;
}

function computeTokenInFee(c: number) {
  if (c >= 90) return BASE_FEE;
  const d = 90 - c;

  // piecewise slope: 0.015 / 0.03 / 0.05, approximated in integer math for UI only.
  // BASE_FEE * (1 + d * slope)
  let multPpm: number;
  if (c >= 70) {
    multPpm = 1_000_000 + Math.round(d * 15_000); // 0.015
  } else if (c >= 50) {
    multPpm = 1_000_000 + Math.round(d * 30_000); // 0.03
  } else {
    multPpm = 1_000_000 + Math.round(d * 50_000); // 0.05
  }
  return Math.round((BASE_FEE * multPpm) / 1_000_000);
}

function computeTokenOutFee(c: number) {
  return Math.round((BASE_FEE * c) / 100);
}

export function selectFeeUnits(zeroForOne: boolean, c0: number, c1: number) {
  const tokenInC = zeroForOne ? c0 : c1;
  const tokenOutC = zeroForOne ? c1 : c0;

  const feeIn = computeTokenInFee(tokenInC);
  const feeOut = computeTokenOutFee(tokenOutC);
  const fee = Math.max(feeIn, feeOut);
  return clamp(fee, MIN_FEE, MAX_FEE);
}

