#!/usr/bin/env bash

# Ensure the deployer key is set
if [[ -z "$DEPLOYER_PRIVATE_KEY" ]]; then
  echo "The DEPLOYER_PRIVATE_KEY environment variable must be set"
  exit 1
fi
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
pushd $SCRIPT_DIR/..

# Deployer position
export INIT_DEPOSIT_AMOUNT=1000000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000000
export INIT_LONG_LIQPRICE=1000000000000000000000 # $1000

# RPC URL, can be customized but defaults to localhost/anvil for testing
: "${RPC_URL:=http://localhost:8545}"

CHAIN_ID=$(cast chain-id -r "$RPC_URL")

# Deploy mocks
forge script --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/00_DeploySepoliaMocks.s.sol:DeploySepoliaMocks --broadcast

BROADCAST="broadcast/00_DeploySepoliaMocks.s.sol/$CHAIN_ID/run-latest.json"
export SDEX_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.Sdex_.value')
export WSTETH_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.WstETH_.value')
export CHAINLINK_GAS_PRICE_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.MockFastGasGwei_.value')

# Deploy USDN token
forge script --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/01_DeployUsdn.s.sol:DeployUsdn --broadcast

BROADCAST="broadcast/01_DeployUsdn.s.sol/$CHAIN_ID/run-latest.json"
export USDN_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.Usdn_.value')

# Deploy protocol
export ETHERSCAN_API_KEY=XXXXXXXXXXXXXXXXX # not needed but needs to exist
export DEPLOYER_ADDRESS=$(cast wallet address "$DEPLOYER_PRIVATE_KEY")
export FEE_COLLECTOR="$DEPLOYER_ADDRESS"
export PYTH_ADDRESS=0xDd24F84d36BF92C65F92307595335bdFab5Bbd21
export PYTH_ETH_FEED_ID=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
export REDSTONE_ETH_FEED_ID=0x4554480000000000000000000000000000000000000000000000000000000000
export CHAINLINK_ETH_PRICE_ADDRESS=0x694AA1769357215DE4FAC081bf1f309aDC325306
export CHAINLINK_ETH_PRICE_VALIDITY=3720
export CHAINLINK_GAS_PRICE_VALIDITY=7500
export GET_WSTETH=false

forge script --non-interactive --private-key "$DEPLOYER_PRIVATE_KEY" -f "$RPC_URL" script/02_Deploy.s.sol:Deploy --broadcast

popd
