#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

# Anvil RPC URL
RPC_URL=http://localhost:8545
# Anvil first test private key
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Setup deployment script environment variables
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export FEE_COLLECTOR=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export WSTETH_ADDRESS=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export INIT_DEPOSIT_AMOUNT=1000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000
export PYTH_ADDRESS=0x4305FB66699C3B2702D4d05CF36551390A4c69C6
export PYTH_STETH_PRICE_ID=0x846ae1bdb6300b817cee5fdee2a6da192775030db5615b94a465f53bd40850b5
export CHAINLINK_STETH_PRICE_ADDRESS=0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8
export GET_WSTETH=true

# Execute in the context of the project's root
pushd $SCRIPT_DIR/..

forge script --non-interactive --private-key $DEPLOYER_PRIVATE_KEY -f $RPC_URL script/Deploy.s.sol --broadcast

popd
