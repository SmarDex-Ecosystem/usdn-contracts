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
export SDEX_ADDRESS=0x5de8ab7e27f6e7a1fff3e5b337584aa43961beef
export WSTETH_ADDRESS=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export INIT_DEPOSIT_AMOUNT=1000000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000000
export PYTH_ADDRESS=0x4305FB66699C3B2702D4d05CF36551390A4c69C6
export PYTH_ETH_FEED_ID=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
export REDSTONE_ETH_FEED_ID=0x4554480000000000000000000000000000000000000000000000000000000000
export CHAINLINK_ETH_PRICE_ADDRESS=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
export CHAINLINK_ETH_PRICE_VALIDITY=3720
export CHAINLINK_GAS_PRICE_ADDRESS=0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C
export CHAINLINK_GAS_PRICE_VALIDITY=7500
export GET_WSTETH=true

# Execute in the context of the project's root
pushd $SCRIPT_DIR/..

forge script --non-interactive --private-key $DEPLOYER_PRIVATE_KEY -f $RPC_URL script/02_Deploy.s.sol:Deploy --broadcast

popd
