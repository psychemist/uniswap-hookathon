import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";

import { makePublicClient } from "../eth/clients";
import { erc4626VaultAbi, pegSentinelHookAbi, pegSentinelReceiverAbi } from "../eth/abis";
import { shortAddr, fmtInt } from "../lib/format";
import { feeUnitsToBps, selectFeeUnits } from "../lib/fee";
import { Card, Pill, ProgressBar, StatRow } from "./ui";

function confidenceTone(c?: number) {
  if (c === undefined) return "neutral" as const;
  if (c >= 90) return "good" as const;
  if (c >= 70) return "warn" as const;
  return "bad" as const;
}

export function Dashboard(props: {
  rpcUrl: string;
  chainId: number;
  hook?: Address;
  receiver?: Address;
  vault?: Address;
  tokens: Array<{ label: string; address: Address }>;
}) {
  const client = makePublicClient(props.rpcUrl, props.chainId);

  const hookMeta = useQuery({
    queryKey: ["hookMeta", props.hook, props.rpcUrl],
    enabled: Boolean(props.hook),
    queryFn: async () => {
      const [receiver, vault] = await Promise.all([
        client.readContract({ address: props.hook!, abi: pegSentinelHookAbi, functionName: "receiver" }),
        client.readContract({ address: props.hook!, abi: pegSentinelHookAbi, functionName: "vault" }),
      ]);
      return { receiver, vault };
    },
  });

  const receiverMeta = useQuery({
    queryKey: ["receiverMeta", props.receiver, props.rpcUrl],
    enabled: Boolean(props.receiver),
    queryFn: async () => {
      const [reactiveContract, minUpdateInterval] = await Promise.all([
        client.readContract({ address: props.receiver!, abi: pegSentinelReceiverAbi, functionName: "reactiveContract" }),
        client.readContract({ address: props.receiver!, abi: pegSentinelReceiverAbi, functionName: "MIN_UPDATE_INTERVAL" }),
      ]);
      return { reactiveContract, minUpdateInterval };
    },
  });

  const vaultMeta = useQuery({
    queryKey: ["vaultMeta", props.vault, props.rpcUrl],
    enabled: Boolean(props.vault),
    queryFn: async () => {
      const [name, symbol, asset, totalAssets, totalSupply, accruedYield] = await Promise.all([
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "name" }),
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "symbol" }),
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "asset" }),
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "totalAssets" }),
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "totalSupply" }),
        client.readContract({ address: props.vault!, abi: erc4626VaultAbi, functionName: "accruedYield" }),
      ]);
      return { name, symbol, asset, totalAssets, totalSupply, accruedYield };
    },
  });

  const confidences = useQuery({
    queryKey: ["confidences", props.hook, props.tokens, props.rpcUrl],
    enabled: Boolean(props.hook) && props.tokens.length > 0,
    queryFn: async () => {
      const entries = await Promise.all(
        props.tokens.map(async (t) => {
          const c = await client.readContract({
            address: props.hook!,
            abi: pegSentinelHookAbi,
            functionName: "pegConfidence",
            args: [t.address],
          });
          return { ...t, confidence: Number(c) };
        })
      );
      return entries;
    },
  });

  const c0 = confidences.data?.[0]?.confidence ?? 0;
  const c1 = confidences.data?.[1]?.confidence ?? 0;
  const feeZfo = feeUnitsToBps(selectFeeUnits(true, c0, c1));
  const feeOzf = feeUnitsToBps(selectFeeUnits(false, c0, c1));

  return (
    <div className="grid gap-4 lg:grid-cols-12">
      <Card className="lg:col-span-7" title="System" subtitle="Live onchain config (read-only)">
        <div className="grid gap-2">
          <StatRow label="RPC" value={props.rpcUrl} />
          <StatRow label="Chain ID" value={props.chainId} />
          <StatRow label="Hook" value={shortAddr(props.hook)} />
          <StatRow label="Receiver" value={shortAddr(props.receiver)} />
          <StatRow label="Vault" value={shortAddr(props.vault)} />
        </div>

        <div className="mt-4 grid gap-2 rounded-xl border border-white/10 bg-black/20 p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="text-xs text-white/60">Bindings</div>
            <div className="flex items-center gap-2">
              <Pill tone={hookMeta.isLoading ? "neutral" : hookMeta.data?.receiver ? "good" : "bad"}>
                hook.receiver: {shortAddr(hookMeta.data?.receiver as Address | undefined)}
              </Pill>
              <Pill tone={hookMeta.isLoading ? "neutral" : hookMeta.data?.vault ? "good" : "bad"}>
                hook.vault: {shortAddr(hookMeta.data?.vault as Address | undefined)}
              </Pill>
            </div>
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            <StatRow
              label="receiver.reactiveContract"
              value={shortAddr(receiverMeta.data?.reactiveContract as Address | undefined)}
            />
            <StatRow
              label="receiver.MIN_UPDATE_INTERVAL"
              value={receiverMeta.data?.minUpdateInterval?.toString() ?? "—"}
            />
          </div>
        </div>
      </Card>

      <Card className="lg:col-span-5" title="Vault" subtitle="ERC-4626 stats (yield-bearing LP shares)">
        <div className="grid gap-2">
          <StatRow label="name" value={vaultMeta.data?.name ?? "—"} />
          <StatRow label="symbol" value={vaultMeta.data?.symbol ?? "—"} />
          <StatRow label="asset" value={shortAddr(vaultMeta.data?.asset as Address | undefined)} />
          <StatRow label="totalSupply" value={fmtInt(vaultMeta.data?.totalSupply)} />
          <StatRow label="totalAssets" value={fmtInt(vaultMeta.data?.totalAssets)} />
          <StatRow label="accruedYield" value={fmtInt(vaultMeta.data?.accruedYield)} />
        </div>
      </Card>

      <Card className="lg:col-span-7" title="Peg confidence" subtitle="0–100, updated by Reactive callbacks">
        <div className="grid gap-3">
          {props.tokens.length === 0 && (
            <div className="text-sm text-white/60">
              Set <code className="rounded bg-white/5 px-1.5 py-0.5">VITE_TOKEN0</code> and{" "}
              <code className="rounded bg-white/5 px-1.5 py-0.5">VITE_TOKEN1</code>.
            </div>
          )}

          {confidences.data?.map((t) => (
            <div key={t.address} className="rounded-xl border border-white/10 bg-black/20 p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-baseline gap-2">
                  <div className="text-sm font-semibold text-white">{t.label}</div>
                  <div className="font-mono text-xs text-white/50">{shortAddr(t.address)}</div>
                </div>
                <Pill tone={confidenceTone(t.confidence)}>
                  confidence: {t.confidence}
                </Pill>
              </div>
              <div className="mt-3">
                <ProgressBar value={t.confidence} />
              </div>
            </div>
          ))}
        </div>
      </Card>

      <Card className="lg:col-span-5" title="Fee preview" subtitle="Estimated v4 fee units (for visualization)">
        <div className="grid gap-3">
          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <div className="flex items-center justify-between">
              <div className="text-xs text-white/60">Zero for One</div>
              <Pill tone={feeZfo <= 30 ? "good" : feeZfo <= 150 ? "warn" : "bad"}>
                {feeZfo.toFixed(2)} bps
              </Pill>
            </div>
            <div className="mt-2 text-xs text-white/50">
              Swap token0 → token1 (uses confidence of tokenIn/tokenOut).
            </div>
          </div>

          <div className="rounded-xl border border-white/10 bg-black/20 p-4">
            <div className="flex items-center justify-between">
              <div className="text-xs text-white/60">One for Zero</div>
              <Pill tone={feeOzf <= 30 ? "good" : feeOzf <= 150 ? "warn" : "bad"}>
                {feeOzf.toFixed(2)} bps
              </Pill>
            </div>
            <div className="mt-2 text-xs text-white/50">
              Swap token1 → token0.
            </div>
          </div>

          <div className="text-xs leading-relaxed text-white/45">
            This panel mirrors the onchain fee selection logic for demo clarity; the authoritative fee is computed by
            the hook at swap time.
          </div>
        </div>
      </Card>
    </div>
  );
}

