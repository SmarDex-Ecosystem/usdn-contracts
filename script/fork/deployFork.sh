#!/usr/bin/env bash

# Path of the script folder (so that the script can be invoked from somewhere else than the project's root).
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

# Execute in the context of the project's root.
pushd $SCRIPT_DIR/../.. >/dev/null

# Anvil RPC URL.
rpcUrl=http://localhost:8545

# Anvil first test private key.
deployerPrivateKey=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploying USDN protocol with wStEth as collateral token.
forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" ./script/fork/DeployUsdnAndShortdnFork.s.sol:DeployUsdnAndShortdnFork --broadcast --force

# Extract chain id from anvil.
chainId=$(cast chain-id -r "$rpcUrl")

# Extract deployment log from forge.
DEPLOYMENT_LOG=$(cat "./broadcast/DeployUsdnAndShortdnFork.s.sol/$chainId/run-latest.json")

# Extract struct values from deployment log
STRUCT_VALUES=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.deployedUsdnAndShortdn.value' | tr -d '()' | tr ',' '\n')
STRUCT_ARRAY=($(echo "$STRUCT_VALUES"))

# Extract data for birth block/time (get first Usdn token CREATE transaction)
USDN_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq -r '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash' | head -1)
USDN_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == \"$USDN_TX_HASH\")")

# Extract and save important data from deployment log.
FORK_ENV_DUMP=$(
    cat <<EOF
WSTETH_ORACLE_MIDDLEWARE_ADDRESS=${STRUCT_ARRAY[0]}
LIQUIDATION_REWARDS_MANAGER_WSTETH_ADDRESS=${STRUCT_ARRAY[1]}
REBALANCER_USDN_ADDRESS=${STRUCT_ARRAY[2]}
USDN_TOKEN_ADDRESS=${STRUCT_ARRAY[3]}
WUSDN_TOKEN_ADDRESS=${STRUCT_ARRAY[4]}
USDN_PROTOCOL_USDN_ADDRESS=${STRUCT_ARRAY[5]}
WUSDN_TO_ETH_ORACLE_MIDDLEWARE_ADDRESS=${STRUCT_ARRAY[6]}
LIQUIDATION_REWARDS_MANAGER_WUSDN_ADDRESS=${STRUCT_ARRAY[7]}
REBALANCER_SHORTDN_ADDRESS=${STRUCT_ARRAY[8]}
USDN_NO_REBASE_SHORTDN_ADDRESS=${STRUCT_ARRAY[9]}
USDN_PROTOCOL_SHORTDN_ADDRESS=${STRUCT_ARRAY[10]}
USDN_TOKEN_BIRTH_BLOCK=$(echo "$USDN_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_TIME=$(echo "$USDN_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
EOF
)

echo "Fork environment variables:"
echo "$FORK_ENV_DUMP"
echo "$FORK_ENV_DUMP" > .env.fork

popd >/dev/null
