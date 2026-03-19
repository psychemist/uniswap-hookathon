# PegSentinel Deployment

## Prereqs

- **RPCs set**: `UNICHAIN_SEPOLIA_RPC`, `REACTIVE_LASNA_RPC`
- **Broadcaster key set**: `DEPLOYER_PRIVATE_KEY`
- **Funded EOA** on both networks for gas

## Unichain Sepolia deploy

Set:

- **REACTIVE_CONTRACT**: the authorized caller for `PegSentinelReceiver.updateConfidence()` on Unichain (typically the Reactive callback gateway address)
- **VAULT_ASSET**: ERC20 asset for the ERC-4626 vault (typically bridged USDC on Unichain)

Run:

```bash
cd peg-sentinel
forge script script/Deploy.s.sol:DeployScript --rpc-url "$UNICHAIN_SEPOLIA_RPC" --broadcast
```

Record the printed addresses:

- `hook`
- `receiver`
- `vault`
- `lendingAdapter`

## Reactive Lasna deploy

Set:

- **UNICHAIN_RECEIVER**: the Unichain receiver address from the previous step
- **UNICHAIN_USDC / UNICHAIN_DAI / UNICHAIN_USDT**: Unichain token addresses that the RSC should reference in callbacks

Run:

```bash
cd peg-sentinel
forge script script/DeployReactive.s.sol:DeployReactiveScript --rpc-url "$REACTIVE_LASNA_RPC" --broadcast
```

Record:

- `rsc` (Reactive contract address)

## Initialize pool + seed liquidity

Set:

- **HOOK**: the hook address
- **TOKEN0 / TOKEN1**: the two ERC20 addresses you want to pair
- (optional) `STARTING_PRICE_X96`, `TICK_SPACING`, `LIQ_TOKEN0`, `LIQ_TOKEN1`

Run:

```bash
cd peg-sentinel
forge script script/InitPool.s.sol:InitPoolScript --rpc-url "$UNICHAIN_SEPOLIA_RPC" --broadcast
```

## Verification checklist

- **Hook address flags**: bottom 14 bits encode `BEFORE_SWAP`, `AFTER_SWAP`, `AFTER_ADD_LIQUIDITY`, `AFTER_REMOVE_LIQUIDITY`
- **Receiver bound**: `PegSentinelHook.receiver()` equals the deployed receiver
- **Vault bound**: `PegSentinelHook.vault()` equals the deployed vault
- **Dynamic fee pool**: pool initialized with `LPFeeLibrary.DYNAMIC_FEE_FLAG` and your hook address
- **Reactive auth**: `PegSentinelReceiver.reactiveContract()` matches your expected gateway
- **Callbacks work**: a call from `REACTIVE_CONTRACT` to `PegSentinelReceiver.updateConfidence()` updates `PegSentinelHook.pegConfidence(token)`

