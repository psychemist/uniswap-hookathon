import type { Address } from "viem";

export function shortAddr(a?: Address) {
  if (!a) return "—";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

export function fmtInt(n?: bigint) {
  if (n === undefined) return "—";
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(
    Number(n)
  );
}

export function fmtPct(n?: number, digits = 0) {
  if (n === undefined || Number.isNaN(n)) return "—";
  return `${n.toFixed(digits)}%`;
}

