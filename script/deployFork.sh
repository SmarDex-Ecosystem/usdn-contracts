#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

# Anvil RPC URL
rpcUrl=http://localhost:8545
# Anvil first test private key
deployerPrivateKey=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Setup deployment script environment variables
export DEPLOYER_ADDRESS=$(cast wallet address --private-key "$deployerPrivateKey") #0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export INIT_LONG_AMOUNT=1000000000000000000000
export GET_WSTETH=true

forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" script/01_DeployProtocol.s.sol:DeployProtocol --broadcast

chainId=$(cast chain-id -r "$rpcUrl")
DEPLOYMENT_LOG=$(cat "broadcast/01_DeployProtocol.s.sol/$chainId/run-latest.json")

USDN_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash')
USDN_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_TX_HASH)")
USDN_PROTOCOL_TX_HASH=$(echo "$DEPLOYMENT_LOG" | jq '.transactions[] | select(.contractName == "ERC1967Proxy" and .transactionType == "CREATE") | .hash')
USDN_PROTOCOL_RECEIPT=$(echo "$DEPLOYMENT_LOG" | jq ".receipts[] | select(.transactionHash == $USDN_PROTOCOL_TX_HASH)")

USDN_PROTOCOL_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.UsdnProtocol_.value' | xargs printf "%s\n")

FORK_ENV_DUMP=$(
    cat <<EOF
SDEX_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.Sdex_.value' | xargs printf "%s\n")
USDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.Usdn_.value' | xargs printf "%s\n")
WUSDN_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.Wusdn_.value' | xargs printf "%s\n")
WSTETH_TOKEN_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.WstETH_.value' | xargs printf "%s\n")
REBALANCER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.Rebalancer_.value' | xargs printf "%s\n")
WSTETH_ORACLE_MIDDLEWARE_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.WstEthOracleMiddleware_.value' | xargs printf "%s\n")
LIQUIDATION_REWARDS_MANAGER_ADDRESS=$(echo "$DEPLOYMENT_LOG" | jq '.returns.LiquidationRewardsManager_.value' | xargs printf "%s\n")
USDN_PROTOCOL_ADDRESS=$(echo "$USDN_PROTOCOL_ADDRESS")
USDN_PROTOCOL_BIRTH_BLOCK=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_PROTOCOL_BIRTH_TIME=$(echo "$USDN_PROTOCOL_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_BLOCK=$(echo "$USDN_RECEIPT" | jq '.blockNumber' | xargs printf "%d\n")
USDN_TOKEN_BIRTH_TIME=$(echo "$USDN_RECEIPT" | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")
EOF
)

echo "Fork environment variables:"
echo "$FORK_ENV_DUMP"
echo "$FORK_ENV_DUMP" > .env.fork

#####
# Admin set roles
#####

rolesArr=(
    "ADMIN_SET_EXTERNAL_ROLE"
    "ADMIN_SET_OPTIONS_ROLE"
    "ADMIN_SET_PROTOCOL_PARAMS_ROLE"
    "ADMIN_SET_USDN_PARAMS_ROLE"
    "SET_EXTERNAL_ROLE"
    "SET_USDN_PARAMS_ROLE"
    "SET_OPTIONS_ROLE"
    "SET_PROTOCOL_PARAMS_ROLE"
    "ADMIN_CRITICAL_FUNCTIONS_ROLE"
    "ADMIN_PROXY_UPGRADE_ROLE"
    "ADMIN_PAUSER_ROLE"
    "ADMIN_UNPAUSER_ROLE"
    "CRITICAL_FUNCTIONS_ROLE"
    "PROXY_UPGRADE_ROLE"
    "PAUSER_ROLE"
    "UNPAUSER_ROLE"
)

for role in "${rolesArr[@]}"; do

    echo "Encode role: $role"
    
    # Encode role
    encodedRole=$(cast keccak "$role")
    echo "Encoded role: $encodedRole"
    
    # Send transaction
    echo -e "\nGranting role $role to $DEPLOYER_ADDRESS..."
    cast send $USDN_PROTOCOL_ADDRESS \
        --from $DEPLOYER_ADDRESS \
        "grantRole(bytes32 role, address account)" \
        $encodedRole $DEPLOYER_ADDRESS \
        --private-key $deployerPrivateKey
    echo "Role $role granted successfully."
done

popd >/dev/null
