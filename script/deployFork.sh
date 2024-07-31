#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

# Anvil RPC URL
RPC_URL=http://localhost:8545
# Anvil first test private key
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Setup deployment script environment variables
# FORK_CHAIN_ID should be set before running the script. If not specified, 31337 is assumed.
export ETHERSCAN_API_KEY=XXXXXXXXXXXXXXXXX # not needed but needs to exist
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export FEE_COLLECTOR=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export SDEX_ADDRESS=
export WSTETH_ADDRESS=
export INIT_DEPOSIT_AMOUNT=1000000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000000
export PYTH_ADDRESS=0xDd24F84d36BF92C65F92307595335bdFab5Bbd21
export PYTH_ETH_FEED_ID=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
export REDSTONE_ETH_FEED_ID=0x4554480000000000000000000000000000000000000000000000000000000000
export CHAINLINK_ETH_PRICE_ADDRESS=0x694AA1769357215DE4FAC081bf1f309aDC325306
export CHAINLINK_ETH_PRICE_VALIDITY=3720
export CHAINLINK_GAS_PRICE_VALIDITY=7500
export GET_WSTETH=false

# Execute in the context of the project's root
pushd $SCRIPT_DIR/..

forge script --non-interactive --private-key $DEPLOYER_PRIVATE_KEY -f $RPC_URL script/02_Deploy.s.sol:Deploy --broadcast

popd
