#!/usr/bin/env bash

# Ensure the deployer key is set
if [[ -z "$DEPLOYER_PRIVATE_KEY" ]]; then
  echo "The DEPLOYER_PRIVATE_KEY environment variable must be set"
  exit 1
fi
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
pushd $SCRIPT_DIR/..
export ETHERSCAN_API_KEY=XXXXXXXXXXXXXXXXX # not needed but needs to exist

# Deployer position
export INIT_DEPOSIT_AMOUNT="${INIT_DEPOSIT_AMOUNT:=200000000000000000000}" # 200 wstETH by default
export INIT_LONG_AMOUNT="${INIT_LONG_AMOUNT:=200000000000000000000}" # 200 wstETH by default

# RPC URL, can be customized but defaults to localhost/anvil for testing
: "${RPC_URL:=http://localhost:8545}"

CHAIN_ID=$(cast chain-id -r "$RPC_URL")

# Deploy mocks
forge script --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/00_DeploySepoliaMocks.s.sol:DeploySepoliaMocks --broadcast

BROADCAST="broadcast/00_DeploySepoliaMocks.s.sol/$CHAIN_ID/run-latest.json"
export SDEX_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.Sdex_.value')
export WSTETH_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.WstETH_.value')
export CHAINLINK_GAS_PRICE_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.MockFastGasGwei_.value')

# Set wstETH conversion rate
RATE=$(cast call -r https://ethereum-rpc.publicnode.com 0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0 "stEthPerToken()" | tr -d '\n')
RATE_UINT=$(cast to-dec "$RATE" | tr -d '\n')
TXDATA=$(cast mktx --private-key "$DEPLOYER_PRIVATE_KEY" "$WSTETH_ADDRESS" "setStEthPerToken(uint256)" "$RATE_UINT" | tr -d '\n')
cast publish -r "$RPC_URL" "$TXDATA"

# Deploy USDN token
forge script --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/01_DeployUsdn.s.sol:DeployUsdn --broadcast

BROADCAST="broadcast/01_DeployUsdn.s.sol/$CHAIN_ID/run-latest.json"
export USDN_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.Usdn_.value')

# Calculate liquidation price for leverage 2x
export CHAINLINK_ETH_PRICE_ADDRESS=0x694AA1769357215DE4FAC081bf1f309aDC325306
ETH_PRICE=$(cast call -r "$RPC_URL" "$CHAINLINK_ETH_PRICE_ADDRESS" "latestAnswer()" | tr -d '\n')
ETH_PRICE_UINT=$(cast to-dec "$ETH_PRICE" | tr -d '\n')
ETH_PRICE_NORM=$(expr $ETH_PRICE_UINT \* 10000000000)
export INIT_LONG_LIQPRICE=$(expr $ETH_PRICE_NORM \* $RATE_UINT / 2000000000000000000)

# Deploy protocol
export DEPLOYER_ADDRESS=$(cast wallet address "$DEPLOYER_PRIVATE_KEY")
export FEE_COLLECTOR="$DEPLOYER_ADDRESS"
export PYTH_ADDRESS=0xDd24F84d36BF92C65F92307595335bdFab5Bbd21
export PYTH_ETH_FEED_ID=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
export REDSTONE_ETH_FEED_ID=0x4554480000000000000000000000000000000000000000000000000000000000
export CHAINLINK_ETH_PRICE_VALIDITY=3720
export CHAINLINK_GAS_PRICE_VALIDITY=7500
export GET_WSTETH=false

forge script --force --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/02_Deploy.s.sol:Deploy --broadcast

popd
