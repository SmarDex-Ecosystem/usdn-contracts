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
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export INIT_DEPOSIT_AMOUNT=1000000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000000
export GET_WSTETH=true

forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast

DEPLOYMENT_LOG=$(cat broadcast/01_Deploy.s.sol/31337/run-latest.json)

echo $DEPLOYMENT_LOG | jq '.returns' | jq -r 'to_entries[] | "\(.key | sub("_$"; ""))=\(.value.value)"' | sed 's#Sdex#SDEX_TOKEN_ADDRESS#' | sed 's#WstEthOracleMiddleware#WSTETH_ORACLE_MIDDLEWARE_ADDRESS#' | sed 's#UsdnProtocol#USDN_PROTOCOL_ADDRESS#' | sed 's#WstETH#WSTETH_TOKEN_ADDRESS#' | sed 's#Rebalancer#REBALANCER_ADDRESS#' | sed 's#Usdn#USDN_TOKEN_ADDRESS#' | sed 's#LiquidationRewardsManager#LIQUIDATION_REWARDS_MANAGER_ADDRESS#' | sed 's#Wusdn#WUSDN_TOKEN_ADDRESS#' | sort
echo

USDN_TX_HASH=$(echo $DEPLOYMENT_LOG | jq '.transactions[] | select(.contractName == "Usdn" and .transactionType == "CREATE") | .hash')
USDN_RECEIPT=$(echo $DEPLOYMENT_LOG | jq ".receipts[] | select(.transactionHash == $USDN_TX_HASH)")

echo USDN_TOKEN_BIRTH_BLOCK=$(echo $USDN_RECEIPT | jq '.blockNumber' | xargs printf "%d\n")
echo USDN_TOKEN_BIRTH_TIME=$(echo $USDN_RECEIPT | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")

USDN_PROTOCOL_TX_HASH=$(echo $DEPLOYMENT_LOG | jq '.transactions[] | select(.contractName == "ERC1967Proxy" and .transactionType == "CREATE") | .hash')
USDN_PROTOCOL_RECEIPT=$(echo $DEPLOYMENT_LOG | jq ".receipts[] | select(.transactionHash == $USDN_PROTOCOL_TX_HASH)")

echo USDN_PROTOCOL_BIRTH_BLOCK=$(echo $USDN_PROTOCOL_RECEIPT | jq '.blockNumber' | xargs printf "%d\n")
echo USDN_PROTOCOL_BIRTH_TIME=$(echo $USDN_PROTOCOL_RECEIPT | jq '.logs[0].blockTimestamp' | xargs printf "%d\n")

popd >/dev/null
