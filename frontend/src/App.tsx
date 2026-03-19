import { useMemo } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { Address } from "viem";
import { Dashboard } from "./components/Dashboard";
import { env } from "./config/env";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
      staleTime: 3_000,
      refetchInterval: 5_000,
    },
  },
});

export default function App() {
  const tokens = useMemo(
    () =>
      [
        env.token0 ? ({ label: env.token0Label, address: env.token0 } as const) : null,
        env.token1 ? ({ label: env.token1Label, address: env.token1 } as const) : null,
      ].filter(Boolean) as Array<{ label: string; address: Address }>,
    []
  );

  return (
    <QueryClientProvider client={queryClient}>
      <div className="min-h-full">
        <div className="mx-auto w-full max-w-6xl px-5 py-10">
          <header className="flex flex-col gap-3">
            <div className="inline-flex items-center gap-2 text-xs text-white/60">
              <span className="rounded-full border border-white/10 bg-white/5 px-2 py-1">
                Uniswap v4 Hook
              </span>
              <span className="rounded-full border border-white/10 bg-white/5 px-2 py-1">
                Reactive callbacks
              </span>
              <span className="rounded-full border border-white/10 bg-white/5 px-2 py-1">
                ERC-4626 vault shares
              </span>
            </div>

            <h1 className="text-balance text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              PegSentinel
              <span className="text-white/50"> — stability-aware LP protection</span>
            </h1>
            <p className="max-w-3xl text-sm leading-relaxed text-white/70">
              Confidence-driven asymmetric fees for stablecoin pools, updated cross-chain by Reactive Network, with
              composable ERC-4626 vault shares.
            </p>
          </header>

          <main className="mt-8">
            <Dashboard
              hook={env.hook}
              receiver={env.receiver}
              vault={env.vault}
              tokens={tokens}
              rpcUrl={env.rpcUrl}
              chainId={env.chainId}
            />
          </main>

          <footer className="mt-10 border-t border-white/10 pt-6 text-xs text-white/50">
          </footer>
        </div>
      </div>
    </QueryClientProvider>
  );
}
