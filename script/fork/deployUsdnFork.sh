#!/usr/bin/env bash

# Path of the script folder (so that the script can be invoked from somewhere else than the project's root).
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

# Execute in the context of the project's root.
pushd $SCRIPT_DIR/../.. >/dev/null

# Anvil RPC URL.
rpcUrl=http://localhost:8545

# Sourcify verifier URL.
sourcifyVerifierUrl=http://localhost:5555

# Anvil first test private key.
deployerPrivateKey=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Check for verify flag
VERIFY_FLAGS=""
if [[ "$1" == "--verify" ]]; then
    VERIFY_FLAGS="--verify --verifier sourcify --verifier-url $sourcifyVerifierUrl"
fi

# Deploying USDN protocol with wStEth as collateral token using runAndReturnValues.
forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" ./script/fork/DeployUsdnFork.s.sol:DeployUsdnFork --broadcast --force $VERIFY_FLAGS

# Extract chain id from anvil.
chainId=$(cast chain-id -r "$rpcUrl")

# Extract deployment log from forge.
DEPLOYMENT_LOG=$(cat "./broadcast/DeployUsdnFork.s.sol/$chainId/run-latest.json")

# Extract individual return values from deployment log (runAndReturnValues returns 8 values)
WSTETH_ORACLE_MIDDLEWARE=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.wstEthOracleMiddleware_.value')
LIQUIDATION_REWARDS_MANAGER=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.liquidationRewardsManager_.value')
REBALANCER=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.rebalancer_.value')
USDN_TOKEN=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.usdn_.value')
WUSDN_TOKEN=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.wusdn_.value')
USDN_PROTOCOL=$(echo "$DEPLOYMENT_LOG" | jq -r '.returns.usdnProtocol_.value')

# Get SDEX address from USDN protocol contract using cast
SDEX_ADDRESS=$(cast call "$USDN_PROTOCOL" "getSdex()" -r "$rpcUrl" | sed 's/0x000000000000000000000000/0x/')

# Get WSTETH address from USDN protocol contract using cast
WSTETH_ADDRESS=$(cast call "$USDN_PROTOCOL" "getAsset()" -r "$rpcUrl" | sed 's/0x000000000000000000000000/0x/')

# Extract data for birth block/time (get first Usdn token CREATE transaction)
USDN_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq -r '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash' | head -1)
USDN_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == \"$USDN_TX_HASH\")")

# Extract and save important data from deployment log.
FORK_ENV_DUMP=$(
    cat <<EOF
SDEX_TOKEN_ADDRESS=$SDEX_ADDRESS
WSTETH_TOKEN_ADDRESS=$WSTETH_ADDRESS
WSTETH_ORACLE_MIDDLEWARE_ADDRESS=$WSTETH_ORACLE_MIDDLEWARE
LIQUIDATION_REWARDS_MANAGER_WSTETH_ADDRESS=$LIQUIDATION_REWARDS_MANAGER
REBALANCER_USDN_ADDRESS=$REBALANCER
USDN_TOKEN_ADDRESS=$USDN_TOKEN
WUSDN_TOKEN_ADDRESS=$WUSDN_TOKEN
USDN_PROTOCOL_USDN_ADDRESS=$USDN_PROTOCOL
USDN_TOKEN_BIRTH_BLOCK=$(echo "$USDN_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_TIME=$(echo "$USDN_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
EOF
)

echo "USDN Fork environment variables:"
echo "$FORK_ENV_DUMP"
echo "$FORK_ENV_DUMP" > .env.usdn

popd >/dev/null
