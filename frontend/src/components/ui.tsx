import type { PropsWithChildren } from "react";

export function Card(
  props: PropsWithChildren<{ className?: string; title?: string; subtitle?: string }>
) {
  return (
    <section
      className={[
        "rounded-2xl border border-white/10 bg-white/5 p-5 shadow-[0_10px_30px_-20px_rgba(0,0,0,0.65)] backdrop-blur",
        props.className ?? "",
      ].join(" ")}
    >
      {(props.title || props.subtitle) && (
        <header className="mb-4">
          {props.title && (
            <h2 className="text-sm font-semibold tracking-tight text-white">
              {props.title}
            </h2>
          )}
          {props.subtitle && (
            <p className="mt-1 text-xs leading-relaxed text-white/55">
              {props.subtitle}
            </p>
          )}
        </header>
      )}
      {props.children}
    </section>
  );
}

export function StatRow(props: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-white/10 py-2 last:border-b-0">
      <span className="text-xs text-white/55">{props.label}</span>
      <span className="font-mono text-xs text-white/85">{props.value}</span>
    </div>
  );
}

export function Pill(props: { children: React.ReactNode; tone?: "good" | "warn" | "bad" | "neutral" }) {
  const tone =
    props.tone === "good"
      ? "border-emerald-400/20 bg-emerald-400/10 text-emerald-200"
      : props.tone === "warn"
        ? "border-amber-400/20 bg-amber-400/10 text-amber-200"
        : props.tone === "bad"
          ? "border-rose-400/20 bg-rose-400/10 text-rose-200"
          : "border-white/10 bg-white/5 text-white/70";

  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${tone}`}>
      {props.children}
    </span>
  );
}

export function ProgressBar(props: { value: number; max?: number }) {
  const max = props.max ?? 100;
  const pct = Math.max(0, Math.min(1, props.value / max));

  // Color shifts based on value
  const barColor =
    pct >= 0.9
      ? "from-emerald-400 via-emerald-300 to-cyan-300"
      : pct >= 0.7
        ? "from-amber-400 via-yellow-300 to-emerald-300"
        : pct >= 0.5
          ? "from-orange-400 via-amber-400 to-yellow-300"
          : "from-rose-500 via-red-400 to-orange-400";

  return (
    <div className="h-2.5 w-full rounded-full bg-white/10">
      <div
        className={`h-2.5 rounded-full bg-gradient-to-r ${barColor}`}
        style={{
          width: `${pct * 100}%`,
          transition: "width 700ms cubic-bezier(0.4, 0, 0.2, 1), background-color 700ms ease",
        }}
      />
    </div>
  );
}

