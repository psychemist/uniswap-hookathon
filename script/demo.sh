#!/bin/bash
# ========================================
# PegSentinel Demo — Live Depeg Simulation
# ========================================
#
# This script runs an Anvil fork of Unichain Sepolia and simulates
# a depeg event by impersonating the Reactive callback gateway to
# send confidence updates to the PegSentinelReceiver.
#
# The frontend (pointed at localhost:8545) will show the confidence
# scores, fee previews, and vault stats updating in real time.
#
# Usage:
#   1. In frontend/.env set VITE_UNICHAIN_RPC=http://localhost:8545
#   2. Start this script: ./script/demo.sh
#   3. In another terminal: cd frontend && npm run dev
#   4. Record your screen!

set -euo pipefail

# --- Config (from addresses.txt) ---
HOOK="0x4d2F277A4979c850bcC26b78fb4A34F19e9085c0"
RECEIVER="0x82E50Bc6B4E3BBB40abBF2D6fBc8E582286b03dC"
REACTIVE_CALLBACK="0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4"
USDC="0x31d0220469e10c4E71834a79b1f276d740d3768F"
DAI="0x6B175474E89094C44Da98b954EedeAC495271d0F"

RPC="https://sepolia.unichain.org"
ANVIL_RPC="http://localhost:8545"

# Kill any existing Anvil
pkill -f "anvil --fork-url" 2>/dev/null || true
sleep 1

echo "🚀 Starting Anvil fork of Unichain Sepolia..."
anvil --fork-url "$RPC" --port 8545 --auto-impersonate &
ANVIL_PID=$!
sleep 4

echo ""
echo "=== PegSentinel Demo Simulation ==="
echo "Anvil PID: $ANVIL_PID"
echo ""

# Impersonate the reactive callback gateway and fund it
echo "🔑 Impersonating Reactive callback gateway..."
cast rpc anvil_impersonateAccount "$REACTIVE_CALLBACK" --rpc-url "$ANVIL_RPC" > /dev/null 2>&1
cast rpc anvil_setBalance "$REACTIVE_CALLBACK" 0xDE0B6B3A7640000 --rpc-url "$ANVIL_RPC" > /dev/null 2>&1
echo "   ✅ Impersonation ready"

# Helper: update confidence
update_confidence() {
  local token=$1
  local confidence=$2
  local label=$3

  echo "📡 Updating $label confidence to $confidence..."
  cast send "$RECEIVER" \
    "updateConfidence(address,uint8)" \
    "$token" "$confidence" \
    --from "$REACTIVE_CALLBACK" \
    --unlocked \
    --rpc-url "$ANVIL_RPC" \
    > /dev/null 2>&1

  # Read back to confirm
  local result
  result=$(cast call "$HOOK" "pegConfidence(address)(uint8)" "$token" --rpc-url "$ANVIL_RPC")
  echo "   ✅ $label confidence is now: $result"
}

# Mine blocks to satisfy rate limiting (MIN_UPDATE_INTERVAL = 100 blocks)
mine_blocks() {
  local count=${1:-101}
  echo "⛏️  Mining $count blocks (bypassing rate limit)..."
  cast rpc anvil_mine "$(printf '0x%x' "$count")" --rpc-url "$ANVIL_RPC" > /dev/null 2>&1
}

echo ""
echo "=============================="
echo "📊 INITIAL STATE — ALL PEGGED"
echo "=============================="
echo ""

cast call "$HOOK" "pegConfidence(address)(uint8)" "$USDC" --rpc-url "$ANVIL_RPC" | xargs -I{} echo "   USDC confidence: {}"
cast call "$HOOK" "pegConfidence(address)(uint8)" "$DAI"  --rpc-url "$ANVIL_RPC" | xargs -I{} echo "   DAI  confidence: {}"

echo ""
echo "🎬 Press ENTER to start the depeg simulation..."
read -r

# --- Scene 1: Mild USDC deviation ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Scene 1: Chainlink detects mild USDC deviation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mine_blocks
update_confidence "$USDC" 85 "USDC"
echo "   → Fees slightly increase for selling USDC into pool"
echo ""
echo "   Press ENTER to continue..."
read -r

# --- Scene 2: Large DAI transfer detected ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐋 Scene 2: Large DAI transfer anomaly detected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mine_blocks
update_confidence "$DAI" 72 "DAI"
echo "   → Both USDC and DAI now have elevated fees"
echo ""
echo "   Press ENTER to continue..."
read -r

# --- Scene 3: USDC depeg accelerates ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Scene 3: USDC depeg accelerates — Chainlink shows 0.5% deviation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mine_blocks
update_confidence "$USDC" 55 "USDC"
echo "   → Fees for selling USDC now ~3x base fee"
echo "   → Buying USDC becomes cheaper (incentivizing arb)"
echo ""
echo "   Press ENTER to continue..."
read -r

# --- Scene 4: Critical depeg ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚨 Scene 4: CRITICAL — USDC drops to \$0.92"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mine_blocks
update_confidence "$USDC" 20 "USDC"
echo "   → Fees for selling USDC: ~5x base fee (MAX PROTECTION)"
echo "   → LPs are protected from toxic flow"
echo ""
echo "   Press ENTER to continue..."
read -r

# --- Scene 5: Recovery ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Scene 5: RECOVERY — USDC re-pegs, DAI stabilizes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mine_blocks
update_confidence "$USDC" 95 "USDC"
mine_blocks
update_confidence "$DAI" 100 "DAI"
echo "   → Fees return to normal base rate (30 bps)"
echo "   → System is fully automated — no human intervention needed"
echo ""

echo ""
echo "=============================="
echo "📊 FINAL STATE"
echo "=============================="
cast call "$HOOK" "pegConfidence(address)(uint8)" "$USDC" --rpc-url "$ANVIL_RPC" | xargs -I{} echo "   USDC confidence: {}"
cast call "$HOOK" "pegConfidence(address)(uint8)" "$DAI"  --rpc-url "$ANVIL_RPC" | xargs -I{} echo "   DAI  confidence: {}"

echo ""
echo "🎬 Demo complete! Press ENTER to stop Anvil..."
read -r

kill $ANVIL_PID 2>/dev/null
echo "✅ Anvil stopped."
