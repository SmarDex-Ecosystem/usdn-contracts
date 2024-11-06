#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'


abiUsdnProtocolStorage=$(cat "out/UsdnProtocolStorage.sol/UsdnProtocolStorage.json")
abiUsdn=$(cat "out/Usdn.sol/Usdn.json")
abiOracleMiddleware=$(cat "out/OracleMiddleware.sol/OracleMiddleware.json")

select_contract_abi() {    
    while true; do
        printf $'\n'"Select the contract you want to scan :"
        printf "\n1) UsdnProtocol"
        printf "\n2) Usdn"
        printf "\n3) OracleMiddleware"
        read -p $'\n'"Your choice [1-3] : " choice
        case $choice in
        [1]*)
            selectedAbi="$abiUsdnProtocolStorage"
            break
            ;;
        [2]*)
            selectedAbi="$abiUsdn"
            break
            ;;
        [3]*)
            selectedAbi="$abiOracleMiddleware"
            break
            ;;
        *) printf "\n${red}Invalid choice. Please select a valid contract.${nc}\n" ;;
        esac
    done
}

get_input() {
    local prompt="$1"
    local input_variable_name="$2"

    while true; do
        read -p $'\n'"$prompt: " user_input
        user_input=$(printf "$user_input" | xargs)
        if [[ -z "$user_input" ]]; then
            printf "\n${red}This input is required.${nc}\n"
        else
            printf "\n${blue}$prompt: ${nc}$user_input\n"
            eval "$input_variable_name=\"$user_input\""
            break
        fi
    done
}

select_contract_abi
get_input "Enter the contract address" contractAddress
get_input "Enter the RPC URL" rpcUrl
get_input "Enter the block number where the USDN Protocol was deployed" usdnProtocolBirthBlock

# Map of bytes32 to associated role
declare -A abi_roles_map=()
abi_roles_map["0x0000000000000000000000000000000000000000000000000000000000000000"]="DEFAULT_ADMIN_ROLE"

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

printf "Roles scanned on abi:\n"
for key in "${!abi_roles_map[@]}"; do
    printf "Hash: $key, Role: ${abi_roles_map[$key]}\n"
done

# Events in IAccessControl.sol from OpenZeppelin
declare -a events=(
    "RoleGranted(bytes32,address,address)"
    "RoleRevoked(bytes32,address,address)"
    "RoleAdminChanged(bytes32,bytes32,bytes32)"
)
declare -a logs=()
# Loop over each event to fetch logs
for event in "${events[@]}"; do
    printf "\n$blue Fetching logs for event:$nc $event\n"

    # Run cast to get logs for each event and capture output in logs_cast variable
    logs_cast=$(cast logs --rpc-url "$rpcUrl" --from-block "$usdnProtocolBirthBlock" --to-block latest "$event" --address "$contractAddress" -j)
    status=$?

    # Check if the command executed successfully
    if [ $status -ne 0 ]; then
        printf "\n$red Failed to retrieve logs for event:$nc $event\n"
    else
        printf "\n$green Logs fetched successfully for event:$nc $event\n"
        # Filter the output to only include topics, blockNumber and logIndex using jq
        logs_filtered=$(printf "$logs_cast" | jq -c '.[] | {topics: .topics, blockNumber: .blockNumber, logIndex: .logIndex}')

        # Process each filtered output
        for log in $logs_filtered; do
            # Extract the topics array
            second_topic=$(printf "$log" | jq -r '.topics[1]')
            third_topic=$(printf "$log" | jq -r '.topics[2]')
            fourth_topic=$(printf "$log" | jq -r '.topics[3]')
            
            # Add first topic to the log
            log=$(printf "$log" | jq --arg new_topic "$event" '.topics[0] = $new_topic')

            # Replace the second topic with the associated string and add it to the log
            new_second_topic=${abi_roles_map[$second_topic]}
            log=$(printf "$log" | jq --arg new_topic "$new_second_topic" '.topics[1] = $new_topic')

            # Replace the third and fourth topics instead of the hash with the associated role or address and add it to the log
            if [[ "$event" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
                role=${abi_roles_map[$third_topic]}
                log=$(printf "$log" | jq --arg new_topic "$role" '.topics[2] = $new_topic')

                role=${abi_roles_map[$fourth_topic]}
                log=$(printf "$log" | jq --arg new_topic "$role" '.topics[3] = $new_topic')
                
            elif [ "$event" == "RoleGranted(bytes32,address,address)" ] || [ "$event" == "RoleRevoked(bytes32,address,address)" ]; then
                address=$(cast parse-bytes32-address "$third_topic")
                log=$(printf "$log" | jq --arg new_topic "$address" '.topics[2] = $new_topic')

                address=$(cast parse-bytes32-address "$fourth_topic")
                log=$(printf "$log" | jq --arg new_topic "$address" '.topics[3] = $new_topic')
            fi

            # Convert blockNumber from hex to decimal and replace the blockNumber in the log
            block_number=$(printf "$log" | jq -r '.blockNumber')
            decimal_block_number=$((block_number))
            log=$(printf "$log" | jq --argjson new_block_number "$decimal_block_number" '.blockNumber = $new_block_number')

            # Convert logIndex from hex to decimal and replace the logIndex in the log
            log_index=$(printf "$log" | jq -r '.logIndex')
            decimal_log_index=$((log_index))
            log=$(printf "$log" | jq --argjson new_log_index "$decimal_log_index" '.logIndex = $new_log_index')

            # Append the modified log to the logs array
            logs+=("$log")
        done
    fi
done

# Exit if no logs were found
if [[ -z "$logs" || "$logs" == "[]" ]]; then
    printf "\n${red}No logs were found. Exiting the script. Verify the RPC URL and contract address.${nc}\n"
    exit 1
fi

# Sort the logs by block number and log index
sorted_logs=$(printf "%s\n" "${logs[@]}" | jq -s 'sort_by(.blockNumber, .logIndex)')
printf "\n$green Sorted logs by block number and logIndex:$nc\n"
printf "$sorted_logs" | jq -c '.[]'
mapfile -t sorted_logs <<< "$(printf "$sorted_logs" | jq -c '.[]')"


# Create a json and csv output with the roles, admin role and addresses granted

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

# Add roles that have not been granted to any address
for role in "${!abi_roles_map[@]}"; do
    if [[ -z "${roles[${abi_roles_map[$role]}]}" ]]; then
        json_output+=$(jq -n \
            --arg role "${abi_roles_map[$role]}" \
            --arg admin "DEFAULT_ADMIN_ROLE" \
            --argjson addresses '["DEFAULT_ADMIN_ROLE"]' \
            '{Role: $role, Role_admin: $admin, Addresses: $addresses}'), 
    fi
done

# Reorder JSON
json_output="${json_output%,}]"
json_output=$(printf "%s" "$json_output" | jq 'sort_by(
    if .Role == "DEFAULT_ADMIN_ROLE" then 0 
    elif .Role | startswith("ADMIN_") then 1 
    else 2 
    end
)')

process_output() {
    local output_type="$1"
    local output_data="$2"
    local file_name="$3"
    local header="$4" # Optional, used for CSV headers

    while true; do
        read -p $'\n'"Do you want to save the $output_type to a file (y), display it on the screen (d), or do nothing (n)? " choice
        case $choice in
        [Yy]*)
            # Save the output to a file
            printf "%s\n" "$header" > "$file_name"
            printf "%s\n" "$output_data" >> "$file_name"
            printf "%s saved to file: %s\n" "$output_type" "$file_name"
            break
            ;;
        [Dd]*)
            # Display the output on the screen
            printf "%s\n" "$header"
            printf "%s\n" "$output_data"
            break
            ;;
        [Nn]*)
            break
            ;;
        *)
            printf "\n$red Please answer with yes (Y/y), display (D/d) or nothing (N/n).$nc\n"
            ;;
        esac
    done
}

# JSON output processing
json_output_processed=$(printf "%s" "$json_output" | jq .)
process_output "JSON" "$json_output_processed" "roles.json"

# CSV output processing
csv_output=$(printf "%s" "$json_output" | jq -r '.[] | [.Role, .Role_admin, (.Addresses | join(","))] | @csv')
process_output "CSV" "$csv_output" "roles.csv" "Role,Role_admin,Addresses"
