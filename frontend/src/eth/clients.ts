import { createPublicClient, http } from "viem";

export function makePublicClient(rpcUrl: string, chainId: number) {
  // Minimal custom chain transport; for read-only calls we only need id.
  return createPublicClient({
    chain: {
      id: chainId,
      name: `chain-${chainId}`,
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [rpcUrl] } },
    },
    transport: http(rpcUrl),
  });
}

