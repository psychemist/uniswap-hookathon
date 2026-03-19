# PegSentinel — Stability-Aware LP Protection for Uniswap v4

> **Uniswap Hook Incubator (UHI) Hookathon Submission**

PegSentinel is a Uniswap v4 hook system that **automatically protects LPs in stablecoin pools during depeg events** using cross-chain intelligence from Reactive Network and yield-bearing ERC-4626 vault shares on Unichain.

When USDC depegged to $0.87 in March 2023, LPs lost over $100M in impermanent loss — with no way to react in time. PegSentinel makes this protection automatic, real-time, and fully on-chain.

---

## Demo Video

**[Watch the demo →](https://www.loom.com/share/5cf7e5874d7d4ce08ce09baafcada51e)**

---

## Why It Matters

- **LP protection without governance**: Confidence updates are automated via Reactive Network, removing the need for manual multisig intervention during volatile depeg events.
- **Asymmetric fee curve**: A novel mechanism where swaps that worsen pool imbalance during a depeg are penalized with higher fees, while restorative swaps are incentivized with lower fees.
- **Composable LP shares**: Positions are tokenized as ERC-4626 shares, making Uniswap v4 LP positions instantly usable as collateral or within other DeFi strategies on Unichain.
- **Reactive is essential**: Leverages cross-chain intelligence to bring Ethereum mainnet health signals to Unichain hooks in real-time.

---

## How It Works

### 1. Cross-Chain Monitoring (Reactive Network)

A Reactive Smart Contract (RSC) on Reactive Network subscribes to **live Ethereum mainnet events**:

| Signal | Source Contract | Event |
|---|---|---|
| USDC/USD price | Chainlink `0x8fFf…18f6` | `AnswerUpdated` |
| DAI/USD price  | Chainlink `0xAed0…1ee9` | `AnswerUpdated` |
| USDT/USD price | Chainlink `0x3E7d…e32D` | `AnswerUpdated` |
| Large transfers | USDC/DAI ERC-20 | `Transfer` (≥$20M) |
| MakerDAO stress | Vat `0x35D1…492B` | `fold` |

The RSC computes a **peg confidence score** (0–100) per token and fires cross-chain callbacks to Unichain when scores change significantly.

**Code → [`src/PegSentinelReactive.sol`](src/PegSentinelReactive.sol)**

### 2. Asymmetric Dynamic Fees (Uniswap v4 Hook on Unichain)

When confidence drops, the hook applies **asymmetric fees** at swap time:

- **Selling a depegging stablecoin** into the pool → fees increase up to **5× base** (protecting LPs from toxic flow)
- **Buying the depegging stablecoin** → fees decrease (incentivizing arbitrageurs to restore the peg)

| Confidence | Selling Fee | Buying Fee |
|---|---|---|
| 100 (pegged) | 30 bps (base) | 30 bps |
| 85 (mild) | ~32 bps | ~25 bps |
| 55 (distressed) | ~62 bps | ~17 bps |
| 20 (critical) | ~135 bps | ~6 bps |

**Code → [`src/PegSentinelHook.sol`](src/PegSentinelHook.sol), [`src/libraries/FeeComputation.sol`](src/libraries/FeeComputation.sol)**

### 3. ERC-4626 Vault Shares (Unichain)

LP positions are wrapped as **yield-bearing vault tokens**:
- Accrue swap fees automatically → shares appreciate over time
- ERC-4626 compliant → directly usable as **lending collateral** on Unichain
- Supports rehypothecation of idle liquidity via a lending adapter

**Code → [`src/PegSentinelVault.sol`](src/PegSentinelVault.sol)**

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   ETHEREUM MAINNET                       │
│  Chainlink feeds · USDC/DAI transfers · MakerDAO Vat    │
└──────────────────────────┬──────────────────────────────┘
                           │ event subscriptions
┌──────────────────────────▼──────────────────────────────┐
│                  REACTIVE NETWORK                        │
│  PegSentinelReactive.sol                                │
│  → Subscribes to mainnet events                         │
│  → Computes per-token confidence scores                 │
│  → Fires cross-chain callbacks to Unichain              │
└──────────────────────────┬──────────────────────────────┘
                           │ callback (tx)
┌──────────────────────────▼──────────────────────────────┐
│                      UNICHAIN                            │
│                                                         │
│  PegSentinelReceiver.sol                                │
│  → Validates RSC origin, rate-limits updates            │
│  → Forwards to hook                                     │
│                                                         │
│  PegSentinelHook.sol (Uniswap v4)                       │
│  → beforeSwap: asymmetric dynamic fees                  │
│  → afterSwap: accrue yield to vault                     │
│  → afterAddLiquidity: mint vault shares                 │
│  → afterRemoveLiquidity: burn vault shares              │
│                                                         │
│  PegSentinelVault.sol (ERC-4626)                        │
│  → Yield-bearing LP shares                              │
│  → Composable as lending collateral                     │
└─────────────────────────────────────────────────────────┘
```

### High-level Dataflow

1. **Ethereum mainnet signals** are observed by Reactive Network:
   - Chainlink stablecoin feeds (`AnswerUpdated`), large transfers, and MakerDAO stress events.
2. **`PegSentinelReactive`** computes a per-token **confidence score** (0–100).
3. When confidence moves significantly, **Reactive emits a callback** to Unichain.
4. **`PegSentinelReceiver`** validates the caller and rate-limits updates, then calls the hook.
5. **`PegSentinelHook`** applies confidence-aware fees at swap time and accrues fees to the vault.
6. **`PegSentinelVault`** tokenizes LP exposure as ERC-4626 shares, tracking liquidity and accrued yield.

### On-Chain Components

- **`PegSentinelHook.sol` (Unichain)**: Uniswap v4 hook that overrides fees in `beforeSwap`, mints/burns vault shares on liquidity updates, and accrues fee-yield in `afterSwap`.
- **`PegSentinelReceiver.sol` (Unichain)**: Secure callback entrypoint for Reactive Network. Enforces origin checks, per-token rate limiting, and confidence bounds.
- **`PegSentinelVault.sol` (Unichain)**: ERC-4626 vault representing LP exposure. Swap fees are reflected in `totalAssets()` making shares yield-bearing.
- **`PegSentinelReactive.sol` (Reactive Network)**: Reactive Smart Contract (RSC) that subscribes to mainnet events and computes the confidence score.

---

## Security Properties

- **Authenticated Updates**: Only the authorized Reactive RSC can update confidence scores, enforced by `onlyReactiveContract`.
- **Rate Limiting**: Updates are throttled by `MIN_UPDATE_INTERVAL` blocks per token to prevent manipulation.
- **Immutable Bindings**: Critical contract relationships (Hook → Receiver, Hook → Vault) are one-time set or immutable.
- **Non-reentrant**: Core entry points are protected against reentrancy.

---

## Technical Stats

- **Contract Sizes**:
  - `PegSentinelHook`: ~7.0 KB
  - `PegSentinelVault`: ~8.0 KB
  - `PegSentinelReceiver`: ~1.7 KB
  - `PegSentinelReactive`: ~4.6 KB
- **Test Coverage**: 59 tests passing (unit + integration), including fork-capable integration scaffolding.

---

## Demo Flow

1. **Deploy on Unichain**: Run `script/Deploy.s.sol` to deploy the Hook, Receiver, and Vault.
2. **Initialize Pool**: Create a pool with `LPFeeLibrary.DYNAMIC_FEE_FLAG`.
3. **Normal Swap**: Execute a swap and observe `totalAssets()` in the vault increasing from fees.
4. **Simulate Depeg**: Update confidence to `60` via the Receiver.
5. **Impact**: Observe that swaps in the depeg direction now incur significantly higher fees.

---

## Partner Integrations

### Unichain
PegSentinel is **deployed on Unichain Sepolia**. The hook, receiver, and vault contracts all run on Unichain. The ERC-4626 vault shares are designed as **yield-bearing tokens** for Unichain lending markets, qualifying for the Unichain tokenized strategies track.

- **Hook**: [`src/PegSentinelHook.sol`](src/PegSentinelHook.sol) — v4 hook with `beforeSwap`, `afterSwap`, `afterAddLiquidity`, `afterRemoveLiquidity`
- **Vault**: [`src/PegSentinelVault.sol`](src/PegSentinelVault.sol) — ERC-4626 vault for LP shares
- **Deployment scripts**: [`script/Deploy.s.sol`](script/Deploy.s.sol), [`script/InitPool.s.sol`](script/InitPool.s.sol)

### Reactive Network
PegSentinel is **architecturally dependent on Reactive Network** — the monitored contracts (Chainlink feeds, USDC ERC-20, MakerDAO Vat) all live on Ethereum mainnet. There is no way for a Unichain hook to access this data without cross-chain automation. Reactive is not bolted on — it is required.

- **Reactive Smart Contract**: [`src/PegSentinelReactive.sol`](src/PegSentinelReactive.sol) — subscribes to 6 mainnet event sources
- **Scoring logic**: [`src/libraries/PegScoring.sol`](src/libraries/PegScoring.sol) — peg confidence computation
- **Deployment**: [`script/DeployReactive.s.sol`](script/DeployReactive.s.sol)

---

## Project Structure

```
peg-sentinel/
├── src/
│   ├── PegSentinelHook.sol           # v4 hook — asymmetric fees + vault integration
│   ├── PegSentinelVault.sol          # ERC-4626 yield-bearing LP vault
│   ├── PegSentinelReceiver.sol       # Unichain callback receiver (validates RSC origin)
│   ├── PegSentinelReactive.sol       # Reactive Network RSC (cross-chain monitoring)
│   ├── interfaces/                   # Contract interfaces
│   └── libraries/
│       ├── FeeComputation.sol        # Pure asymmetric fee math
│       └── PegScoring.sol            # Peg confidence scoring model
├── test/
│   ├── unit/                         # Unit tests for all components
│   └── integration/                  # Full-system integration tests
├── script/
│   ├── Deploy.s.sol                  # Unichain deployment
│   ├── DeployReactive.s.sol          # Reactive Network deployment
│   ├── InitPool.s.sol                # Pool initialization
│   └── demo.sh                       # Live depeg simulation script
└── frontend/                         # React dashboard (live on-chain reads)
```

---

## Running Tests

```bash
forge test
```

Tests cover:
- **FeeComputation**: monotonicity, bounds, edge cases (fuzz)
- **PegScoring**: Chainlink deltas, transfer thresholds, MakerDAO stress, time recovery
- **PegSentinelHook**: access control, fee overrides, vault integration
- **PegSentinelVault**: ERC-4626 lifecycle, yield accrual
- **PegSentinelReceiver**: origin validation, rate limiting
- **Integration**: full system end-to-end with depeg simulation

---

## Frontend

A React + Tailwind dashboard that reads live on-chain state:

```bash
cd frontend
cp .env.example .env  # Fill in deployed addresses
npm install
npm run dev
```

Shows: peg confidence bars, fee previews, vault stats, system bindings.

---

## Deployment

See [`script/DEPLOYMENT.md`](script/DEPLOYMENT.md) for full instructions.

**Quick start:**
```bash
# 1. Deploy to Unichain Sepolia
forge script script/Deploy.s.sol:DeployScript --rpc-url "$UNICHAIN_SEPOLIA_RPC" --broadcast

# 2. Deploy RSC to Reactive Lasna
forge create src/PegSentinelReactive.sol:PegSentinelReactive \
  --rpc-url "$REACTIVE_LASNA_RPC" --private-key "$DEPLOYER_PRIVATE_KEY" \
  --constructor-args "$UNICHAIN_RECEIVER" "$UNICHAIN_USDC" "$UNICHAIN_DAI" "$UNICHAIN_USDT"
```

---

## Prize Tracks

| Track | Qualification |
|---|---|
| **UHI8 — Dynamic Stablecoin Managers** | Core mechanism: peg-confidence–driven asymmetric fees on stablecoin pools |
| **Unichain — Tokenized Strategies / Yield-Bearing Tokens** | ERC-4626 vault shares directly usable as lending collateral |
| **Reactive Network** | RSC is architecturally required for cross-chain monitoring of mainnet signals |

---

## License

MIT
