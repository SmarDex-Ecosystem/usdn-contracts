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
forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" ./script/fork/01_DeployUsdnWstethUsdFork_Long.s.sol:DeployUsdnWstethFork --broadcast --force

# Extract chain id from anvil.
chainId=$(cast chain-id -r "$rpcUrl")

# Extract deployment log from forge.
DEPLOYMENT_LOG=$(cat "./broadcast/01_DeployUsdnWstethUsdFork_Long.s.sol/$chainId/run-latest.json")

# Extract data from deployment log.
USDN_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash')
USDN_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_TX_HASH)")
USDN_PROTOCOL_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "ERC1967Proxy" and .transactionType == "CREATE") | .hash')
USDN_PROTOCOL_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_PROTOCOL_TX_HASH)")
USDN_PROTOCOL_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.usdnProtocol_.value' | xargs printf "%s\n")

# Extract and save important data from deployment log.
FORK_ENV_DUMP=$(
    cat <<EOF
SDEX_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.sdex_.value' | xargs printf "%s\n")
USDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.usdn_.value' | xargs printf "%s\n")
WUSDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.wusdn_.value' | xargs printf "%s\n")
WSTETH_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.underlying_.value' | xargs printf "%s\n")
REBALANCER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.rebalancer_.value' | xargs printf "%s\n")
WSTETH_ORACLE_MIDDLEWARE_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.wstEthOracleMiddleware_.value' | xargs printf "%s\n")
LIQUIDATION_REWARDS_MANAGER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.liquidationRewardsManager_.value' | xargs printf "%s\n")
USDN_PROTOCOL_ADDRESS=$(echo "$USDN_PROTOCOL_ADDRESS")
USDN_PROTOCOL_BIRTH_BLOCK=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_PROTOCOL_BIRTH_TIME=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_BLOCK=$(echo "$USDN_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_TIME=$(echo "$USDN_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
EOF
)

forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" ./script/fork/01_DeployUsdnWusdnEthFork_Short.s.sol:DeployUsdnWusdnFork --broadcast --force

# Extract deployment log from forge.
DEPLOYMENT_LOG=$(cat "./broadcast/01_DeployUsdnWstethUsdFork_Long.s.sol/$chainId/run-latest.json")

# Extract data from deployment log.
USDN_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash')
USDN_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_TX_HASH)")
USDN_PROTOCOL_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "ERC1967Proxy" and .transactionType == "CREATE") | .hash')
USDN_PROTOCOL_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_PROTOCOL_TX_HASH)")
USDN_PROTOCOL_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.usdnProtocol_.value' | xargs printf "%s\n")

# # Extract and save important data from deployment log.
# FORK_ENV_DUMP=$(
#     cat <<EOF
# SDEX_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.sdex_.value' | xargs printf "%s\n")
# USDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.usdn_.value' | xargs printf "%s\n")
# WUSDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.wusdn_.value' | xargs printf "%s\n")
# WSTETH_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.underlying_.value' | xargs printf "%s\n")
# REBALANCER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.rebalancer_.value' | xargs printf "%s\n")
# WSTETH_ORACLE_MIDDLEWARE_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.wstEthOracleMiddleware_.value' | xargs printf "%s\n")
# LIQUIDATION_REWARDS_MANAGER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.liquidationRewardsManager_.value' | xargs printf "%s\n")
# USDN_PROTOCOL_ADDRESS=$(echo "$USDN_PROTOCOL_ADDRESS")
# USDN_PROTOCOL_BIRTH_BLOCK=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
# USDN_PROTOCOL_BIRTH_TIME=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
# USDN_TOKEN_BIRTH_BLOCK=$(echo "$USDN_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
# USDN_TOKEN_BIRTH_TIME=$(echo "$USDN_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
# EOF
# )

echo "Fork environment variables:"
echo "$FORK_ENV_DUMP"
echo "$FORK_ENV_DUMP" > .env.fork

popd >/dev/null
