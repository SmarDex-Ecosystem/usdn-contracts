#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/../.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

# ---------------------------------------------------------------------------- #
#                                    Inputs                                    #
# ---------------------------------------------------------------------------- #

# Function to display usage message
usage() {
    printf "${red}Error: Missing required arguments.${nc}\n"
    printf "Usage: $0 --protocol <UsdnProtocolAddress> --rpc-url <RPC_URL> [--block-number <BlockNumber>]\n"
    exit 1
}

# Parse options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --protocol) contractAddressUsdnProtocol="$2"; shift ;;
        --rpc-url) rpcUrl="$2"; shift ;;
        --block-number) usdnProtocolBirthBlock="$2"; shift ;;
        *) usage ;; # Display usage if unexpected argument is found
    esac
    shift
done

# Verify that all required arguments are provided
if [[ -z "$contractAddressUsdnProtocol" || -z "$rpcUrl" ]]; then
    usage
fi

# ---------------------------------------------------------------------------- #
#                                   Variables                                  #
# ---------------------------------------------------------------------------- #

function getContracts() {
    # Get contract address for USDN and OracleMiddleware from UsdnProtocol contract
    contractBytesUsdn=$(cast call "$contractAddressUsdnProtocol" "getUsdn()" --rpc-url "$rpcUrl")
    contractAddressUsdn=$(cast parse-bytes32-address "$contractBytesUsdn")
    contractBytesOracleMiddleware=$(cast call "$contractAddressUsdnProtocol" "getOracleMiddleware()" --rpc-url "$rpcUrl")
    contractAddressOracleMiddleware=$(cast parse-bytes32-address "$contractBytesOracleMiddleware")
    # Get contract address for Rebalancer and LiquidationRewardsManager from UsdnProtocol contract
    contractBytesRebalancer=$(cast call "$contractAddressUsdnProtocol" "getRebalancer()" --rpc-url "$rpcUrl")
    contractAddressRebalancer=$(cast parse-bytes32-address "$contractBytesRebalancer")
    contractBytesLiquidationRewardsManager=$(cast call "$contractAddressUsdnProtocol" "getLiquidationRewardsManager()" --rpc-url "$rpcUrl")
    contractAddressLiquidationRewardsManager=$(cast parse-bytes32-address "$contractBytesLiquidationRewardsManager")
}

getContracts

# Load ABI files
abiUsdnProtocolStorage=$(cat "out/UsdnProtocolConstantsLibrary.sol/UsdnProtocolConstantsLibrary.json")
abiUsdn=$(cat "out/Usdn.sol/Usdn.json")
abiOracleMiddleware=$(cat "out/OracleMiddleware.sol/OracleMiddleware.json")

# Array of contracts to scan
declare -A contracts=(
    ["UsdnProtocol"]=$abiUsdnProtocolStorage
    ["Usdn"]=$abiUsdn
    ["OracleMiddleware"]=$abiOracleMiddleware
)

# List of openzeppelin access control events
declare -a events=(
    "RoleGranted(bytes32,address,address)"
    "RoleRevoked(bytes32,address,address)"
    "RoleAdminChanged(bytes32,bytes32,bytes32)"
)

# Map of bytes32 to associated role
declare -A abi_roles_map=()
abi_roles_map["0x0000000000000000000000000000000000000000000000000000000000000000"]="DEFAULT_ADMIN_ROLE"

# Variables used to store informations at the end of the process logs
declare -A roles
declare -A admin_role
declare -A addresses

# Define an array to store owner information
declare -A owners


# ---------------------------------------------------------------------------- #
#                                Roles scanning                                #
# ---------------------------------------------------------------------------- #

# ----------------------------------- Utils ---------------------------------- #

function createAbiRolesMap(){
    # Get the ABI and select roles
    selectedAbi="${contracts["$1"]}"
    abi_roles=$(echo "$selectedAbi" | jq -r '
      .abi[] |
      select(
        .type == "function" and 
        .stateMutability == "view" and 
        (.inputs | length == 0) and 
        (.outputs | length == 1) and
        (.outputs[0] | .name == "" and .type == "bytes32" and .internalType == "bytes32") and
        (.name | endswith("_ROLE"))
      ) |
      .name
    ')
    
    # Create a map of bytes32 to associated role
    for abi_role in $abi_roles; do
        hash=$(cast keccak "$abi_role")
        abi_roles_map["$hash"]="$abi_role"
    done
}

function convertHexToDecimal(){
    # Convert block number and log index to decimal
    block_number=$(printf "$log" | jq -r '.blockNumber')
    decimal_block_number=$((block_number))
    log=$(printf "$log" | jq --argjson new_block_number "$decimal_block_number" '.blockNumber = $new_block_number')
    log_index=$(printf "$log" | jq -r '.logIndex')
    decimal_log_index=$((log_index))
    log=$(printf "$log" | jq --argjson new_log_index "$decimal_log_index" '.logIndex = $new_log_index')
}

function sortByBlockNumberAndLogIndex(){
    # Sort logs by block number and logIndex
    sorted_logs=$(printf "%s\n" "${logs[@]}" | jq -s 'sort_by(.blockNumber, .logIndex)')
    printf "\n${green}Sorted logs for $contract_name by block number and logIndex:${nc}\n"
    mapfile -t sorted_logs <<< "$(printf "$sorted_logs" | jq -c '.[]')"
}

function saveJsonAndCsv(){
    json_output_processed=$(printf "%s" "$json_output" | jq .)
    echo "$json_output_processed" > "${contract_name}_roles.json"
    printf "${green}${contract_name} roles JSON saved to ${contract_name}_roles.json${nc}\n"
    csv_output=$(printf "%s" "$json_output" | jq -r '.[] | [.Role, .Role_admin, (.Addresses | join(","))] | @csv')
    printf "Role,Role_admin,Addresses\n$csv_output" > "${contract_name}_roles.csv"
    printf "${green}${contract_name} roles CSV saved to ${contract_name}_roles.csv${nc}\n"
}

function createJson(){
    json_output="["
    for role in "${!roles[@]}"; do
        address_list=$(printf "${addresses[$role]}" | tr ' ' '\n' | jq -R . | jq -s .)
        admin_value="${admin_role[$role]}"
        # If admin role is not found, set it to DEFAULT_ADMIN_ROLE
        if [[ -z "$admin_value" ]]; then
            admin_role[$role]="DEFAULT_ADMIN_ROLE"
        fi
        json_output+=$(jq -n \
            --arg role "$role" \
            --arg admin "${admin_role[$role]}" \
            --argjson addresses "$address_list" \
            '{Role: $role, Role_admin: $admin, Addresses: $addresses}'), 
    done
}

function sortJson(){
    # Sort roles by DEFAULT_ADMIN_ROLE, ADMIN_*, and others
    json_output="${json_output%,}]"
    json_output=$(printf "%s" "$json_output" | jq 'sort_by(
        if .Role == "DEFAULT_ADMIN_ROLE" then 0 
        elif .Role | startswith("ADMIN_") then 1 
        else 2 
        end
    )')
}

function processLogs(){
    # Loop through each log and extract role, address, and admin_role
    # Addresses will be added or removed based on the event
    # The admin_role will be updated if the event is RoleAdminChanged
    for log in "${sorted_logs[@]}"; do
        event=$(printf "$log" | jq -r '.topics[0]')
        role=$(printf "$log" | jq -r '.topics[1]')
        address=$(printf "$log" | jq -r '.topics[2]')
        admin_role=$(printf "$log" | jq -r '.topics[3]')

        roles["$role"]=1
        if [[ "$event" == "RoleGranted(bytes32,address,address)" ]]; then
            addresses["$role"]+="$address "
        elif [[ "$event" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
            admin_role["$role"]="$admin_role"
        elif [[ "$event" == "RoleRevoked(bytes32,address,address)" ]]; then
            addresses["$role"]="${addresses[$role]//"$address "/}"
        fi
    done
}

function processLog() {
    local log="$1"
    local event="$2"
    
    # Extract topics
    local second_topic=$(printf "$log" | jq -r '.topics[1]')
    local third_topic=$(printf "$log" | jq -r '.topics[2]')
    local fourth_topic=$(printf "$log" | jq -r '.topics[3]')
    
    # Update first topic with event name
    log=$(printf "$log" | jq --arg new_topic "$event" '.topics[0] = $new_topic')
    
    # Update topics based on event type
    if [[ "$event" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
        log=$(updateLogRole "$log" "$second_topic" 1)
        log=$(updateLogRole "$log" "$third_topic" 2)
        log=$(updateLogRole "$log" "$fourth_topic" 3)
    else
        log=$(updateLogRole "$log" "$second_topic" 1)
        log=$(updateLogAddress "$log" "$third_topic" 2)
        log=$(updateLogAddress "$log" "$fourth_topic" 3)
    fi

    convertHexToDecimal
    logs+=("$log")
}

function updateLogRole() {
    local log="$1"
    local topic="$2"
    local index="$3"
    local role=${abi_roles_map[$topic]}
    printf "$log" | jq --arg new_topic "$role" ".topics[$index] = \$new_topic"
}

function updateLogAddress() {
    local log="$1"
    local topic="$2"
    local index="$3"
    local address=$(cast parse-bytes32-address "$topic")
    printf "$log" | jq --arg new_topic "$address" ".topics[$index] = \$new_topic"
}

# ------------------------------------ Run ----------------------------------- #

# Loop through each contract and scan for roles. After scanning, the end result will be saved in a JSON and CSV files
for contract_name in "${!contracts[@]}"; do
    printf "\n${blue}Scanning roles for contract:${nc} $contract_name\n"

    createAbiRolesMap "$contract_name"

    declare -a logs=()
    contractAddressVar="contractAddress${contract_name// /}"

    # Fetch logs for each event. This loop will fetch logs for each event and store them in logs
    for event in "${events[@]}"; do
        printf "${blue}Fetching logs for event:${nc} $event\n"
        logs_cast=$(cast logs --rpc-url "$rpcUrl" --from-block "${usdnProtocolBirthBlock:-0}" --to-block latest "$event" --address "${!contractAddressVar}" --json)
        status=$?

        if [ $status -ne 0 ]; then
            printf "\n${red}Failed to retrieve logs for event:${nc} $event\n"
        else
            logs_filtered=$(printf "$logs_cast" | jq -c '.[] | {topics: .topics, blockNumber: .blockNumber, logIndex: .logIndex}')
            for log in $logs_filtered; do
                processLog "$log" "$event"
            done
        fi
    done

    if [[ -z "$logs" || "$logs" == "[]" ]]; then
        printf "\n${red}No logs were found. Skipping contract: $contract_name.${nc}\n"
        continue
    fi

    sortByBlockNumberAndLogIndex
    processLogs
    createJson
    sortJson
    saveJsonAndCsv

done

# ---------------------------------------------------------------------------- #
#                                Owner scanning                                #
# ---------------------------------------------------------------------------- #

# ----------------------------------- Utils ---------------------------------- #


# Fetch and store owner of Rebalancer contract
function fetchAndStoreOwner() {
    local contractName=$1
    local contractAddress=$2

    printf "${blue}Fetching owner of ${contractName} contract:${nc} $contractAddress\n"
    local bytesOwner=$(cast call "$contractAddress" "owner()" --rpc-url "$rpcUrl")
    local owner=$(cast parse-bytes32-address "$bytesOwner")

    if [[ $? -ne 0 ]]; then
        printf "${red}Failed to retrieve owner of ${contractName} contract${nc}\n"
    else
        owners["$contractName"]=$owner
    fi
}

function saveJson(){
    json_output="["
    for contract in "${!owners[@]}"; do
        json_output+=$(jq -n --arg contract "$contract" --arg owner "${owners[$contract]}" '{Contract: $contract, Owner: $owner}'), 
    done
    json_output="${json_output%,}]"
    json_output=$(printf "%s" "$json_output" | jq .)
    echo "$json_output" > "owners.json"
    printf "${green}Owners JSON saved to owners.json${nc}\n"
}


function saveCsv(){
    csv_output="Contract,Owner\n"
    for contract in "${!owners[@]}"; do
        csv_output+="$contract,${owners[$contract]}\n"
    done
    printf "$csv_output" > "owners.csv"
    printf "${green}Owners CSV saved to owners.csv${nc}\n"
}

# ------------------------------------ Run ----------------------------------- #

fetchAndStoreOwner "Rebalancer" "$contractAddressRebalancer"
fetchAndStoreOwner "LiquidationRewardsManager" "$contractAddressLiquidationRewardsManager"

saveJson
saveCsv

popd >/dev/null
