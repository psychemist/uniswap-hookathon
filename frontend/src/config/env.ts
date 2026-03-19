import { isAddress } from "viem";
import type { Address } from "viem";

function getEnv(key: string): string | undefined {
  const v = import.meta.env[key] as string | undefined;
  if (!v) return undefined;
  const trimmed = v.trim();
  return trimmed.length ? trimmed : undefined;
}

function getAddress(key: string): Address | undefined {
  const v = getEnv(key);
  if (!v) return undefined;
  if (!isAddress(v)) return undefined;
  return v as Address;
}

export const env = {
  rpcUrl: getEnv("VITE_UNICHAIN_RPC") ?? "https://sepolia.unichain.org",
  chainId: Number(getEnv("VITE_CHAIN_ID") ?? "1301"),

  hook: getAddress("VITE_HOOK"),
  receiver: getAddress("VITE_RECEIVER"),
  vault: getAddress("VITE_VAULT"),

  token0: getAddress("VITE_TOKEN0"),
  token1: getAddress("VITE_TOKEN1"),
  token0Label: getEnv("VITE_TOKEN0_LABEL") ?? "Token0",
  token1Label: getEnv("VITE_TOKEN1_LABEL") ?? "Token1",
} as const;

