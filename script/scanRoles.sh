#!/usr/bin/env bash

# Define colors
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

# Load ABI files
abiUsdnProtocolStorage=$(cat "out/UsdnProtocolStorage.sol/UsdnProtocolStorage.json")
abiUsdn=$(cat "out/Usdn.sol/Usdn.json")
abiOracleMiddleware=$(cat "out/OracleMiddleware.sol/OracleMiddleware.json")

# Initialize variables
contractAddressUsdnProtocol=""
rpcUrl=""
usdnProtocolBirthBlock=0

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

contractBytesUsdn=$(cast call "$contractAddressUsdnProtocol" "getUsdn()" --rpc-url "$rpcUrl")
contractAddressUsdn=$(cast parse-bytes32-address "$contractBytesUsdn")

contractBytesOracleMiddleware=$(cast call "$contractAddressUsdnProtocol" "getOracleMiddleware()" --rpc-url "$rpcUrl")
contractAddressOracleMiddleware=$(cast parse-bytes32-address "$contractBytesOracleMiddleware")


# Roles scanning

# Array of contracts to scan
declare -A contracts=(
    ["UsdnProtocol"]=$abiUsdnProtocolStorage
    ["Usdn"]=$abiUsdn
    ["OracleMiddleware"]=$abiOracleMiddleware
)

# Map of bytes32 to associated role
declare -A abi_roles_map=()
abi_roles_map["0x0000000000000000000000000000000000000000000000000000000000000000"]="DEFAULT_ADMIN_ROLE"

for contract_name in "${!contracts[@]}"; do
    printf "\n${blue}Scanning roles for contract:${nc} $contract_name\n"

    # Get the ABI and select roles
    selectedAbi="${contracts[$contract_name]}"
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
    
    for abi_role in $abi_roles; do
        hash=$(cast keccak "$abi_role")
        abi_roles_map["$hash"]="$abi_role"
    done

    # Fetch logs for each relevant event
    declare -a events=(
        "RoleGranted(bytes32,address,address)"
        "RoleRevoked(bytes32,address,address)"
        "RoleAdminChanged(bytes32,bytes32,bytes32)"
    )
    declare -a logs=()
    contractAddressVar="contractAddress${contract_name// /}"

    for event in "${events[@]}"; do
        printf "${blue}Fetching logs for event:${nc} $event\n"
        logs_cast=$(cast logs --rpc-url "$rpcUrl" --from-block "$usdnProtocolBirthBlock" --to-block latest "$event" --address "${!contractAddressVar}" -j)
        status=$?

        if [ $status -ne 0 ]; then
            printf "\n${red}Failed to retrieve logs for event:${nc} $event\n"
        else
            logs_filtered=$(printf "$logs_cast" | jq -c '.[] | {topics: .topics, blockNumber: .blockNumber, logIndex: .logIndex}')
            for log in $logs_filtered; do
                second_topic=$(printf "$log" | jq -r '.topics[1]')
                third_topic=$(printf "$log" | jq -r '.topics[2]')
                fourth_topic=$(printf "$log" | jq -r '.topics[3]')
                
                log=$(printf "$log" | jq --arg new_topic "$event" '.topics[0] = $new_topic')
                role=${abi_roles_map[$second_topic]}
                log=$(printf "$log" | jq --arg new_topic "$role" '.topics[1] = $new_topic')
                if [[ "$event" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
                    role=${abi_roles_map[$third_topic]}
                    log=$(printf "$log" | jq --arg new_topic "$role" '.topics[2] = $new_topic')
                    role=${abi_roles_map[$fourth_topic]}
                    log=$(printf "$log" | jq --arg new_topic "$role" '.topics[3] = $new_topic')
                else
                    address=$(cast parse-bytes32-address "$third_topic")
                    log=$(printf "$log" | jq --arg new_topic "$address" '.topics[2] = $new_topic')
                    address=$(cast parse-bytes32-address "$fourth_topic")
                    log=$(printf "$log" | jq --arg new_topic "$address" '.topics[3] = $new_topic')
                fi

                block_number=$(printf "$log" | jq -r '.blockNumber')
                decimal_block_number=$((block_number))
                log=$(printf "$log" | jq --argjson new_block_number "$decimal_block_number" '.blockNumber = $new_block_number')
                log_index=$(printf "$log" | jq -r '.logIndex')
                decimal_log_index=$((log_index))
                log=$(printf "$log" | jq --argjson new_log_index "$decimal_log_index" '.logIndex = $new_log_index')
                logs+=("$log")
            done
        fi
    done

    if [[ -z "$logs" || "$logs" == "[]" ]]; then
        printf "\n${red}No logs were found. Skipping contract: $contract_name.${nc}\n"
        continue
    fi

    sorted_logs=$(printf "%s\n" "${logs[@]}" | jq -s 'sort_by(.blockNumber, .logIndex)')
    printf "\n${green}Sorted logs for $contract_name by block number and logIndex:${nc}\n"
    mapfile -t sorted_logs <<< "$(printf "$sorted_logs" | jq -c '.[]')"

    declare -A roles
    declare -A admin_role
    declare -A addresses

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

    json_output="["
    for role in "${!roles[@]}"; do
        address_list=$(printf "${addresses[$role]}" | tr ' ' '\n' | jq -R . | jq -s .)
        admin_value="${admin_role[$role]}"
        if [[ -z "$admin_value" ]]; then
            admin_role[$role]="DEFAULT_ADMIN_ROLE"
        fi
        json_output+=$(jq -n \
            --arg role "$role" \
            --arg admin "${admin_role[$role]}" \
            --argjson addresses "$address_list" \
            '{Role: $role, Role_admin: $admin, Addresses: $addresses}'), 
    done

    json_output="${json_output%,}]"
    json_output=$(printf "%s" "$json_output" | jq 'sort_by(
        if .Role == "DEFAULT_ADMIN_ROLE" then 0 
        elif .Role | startswith("ADMIN_") then 1 
        else 2 
        end
    )')

    json_output_processed=$(printf "%s" "$json_output" | jq .)
    echo "$json_output_processed" > "${contract_name}_roles.json"
    printf "${green}${contract_name} roles JSON saved to ${contract_name}_roles.json${nc}\n"

    csv_output=$(printf "%s" "$json_output" | jq -r '.[] | [.Role, .Role_admin, (.Addresses | join(","))] | @csv')
    printf "Role,Role_admin,Addresses\n$csv_output" > "${contract_name}_roles.csv"
    printf "${green}${contract_name} roles CSV saved to ${contract_name}_roles.csv${nc}\n"

done

# Owner scanning

contractBytesRebalancer=$(cast call "$contractAddressUsdnProtocol" "getRebalancer()" --rpc-url "$rpcUrl")
contractAddressRebalancer=$(cast parse-bytes32-address "$contractBytesRebalancer")
contractBytesLiquidationRewardsManager=$(cast call "$contractAddressUsdnProtocol" "getLiquidationRewardsManager()" --rpc-url "$rpcUrl")
contractAddressLiquidationRewardsManager=$(cast parse-bytes32-address "$contractBytesLiquidationRewardsManager")

# Define an array to store owner information
declare -A owners

# Fetch and store owner of Rebalancer contract
printf "${blue}Fetching owner of Rebalancer contract:${nc} $contractAddressRebalancer\n"
bytesOwnerRebalancer=$(cast call "$contractAddressRebalancer" "owner()" --rpc-url "$rpcUrl")
ownerLiquidationRewardsManager=$(cast parse-bytes32-address "$bytesOwnerRebalancer")
if [[ $? -ne 0 ]]; then
    printf "${red}Failed to retrieve owner of Rebalancer contract${nc}\n"
else
    owners["Rebalancer"]="$ownerRebalancer"
fi

# Fetch and store owner of LiquidationRewardsManager contract
printf "${blue}Fetching owner of LiquidationRewardsManager contract:${nc} $contractAddressLiquidationRewardsManager\n"
bytesOwnerLiquidationRewardsManager=$(cast call "$contractAddressLiquidationRewardsManager" "owner()" --rpc-url "$rpcUrl")
ownerLiquidationRewardsManager=$(cast parse-bytes32-address "$bytesOwnerLiquidationRewardsManager")
if [[ $? -ne 0 ]]; then
    printf "${red}Failed to retrieve owner of LiquidationRewardsManager contract${nc}\n"
else
    owners["LiquidationRewardsManager"]="$ownerLiquidationRewardsManager"
fi

# Create JSON output
json_output="["
for contract in "${!owners[@]}"; do
    json_output+=$(jq -n --arg contract "$contract" --arg owner "${owners[$contract]}" '{Contract: $contract, Owner: $owner}'), 
done
json_output="${json_output%,}]"
json_output=$(printf "%s" "$json_output" | jq .)
echo "$json_output" > "owners.json"
printf "${green}Owners JSON saved to owners.json${nc}\n"

# Create CSV output
csv_output="Contract,Owner\n"
for contract in "${!owners[@]}"; do
    csv_output+="$contract,${owners[$contract]}\n"
done
printf "$csv_output" > "owners.csv"
printf "${green}Owners CSV saved to owners.csv${nc}\n"