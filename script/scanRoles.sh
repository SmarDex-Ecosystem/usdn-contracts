#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

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

get_input "Enter the USDN Protocol's address" usdnProtocolAddress
get_input "Enter the RPC URL" rpcUrl

# Map of bytes32 to associated role
declare -A abi_roles_map=()
abi_roles_map["0x0000000000000000000000000000000000000000000000000000000000000000"]="DEFAULT_ADMIN_ROLE"

abi=$(cat "out/UsdnProtocolStorage.sol/UsdnProtocolStorage.json")
abi_roles=$(echo "$abi" | jq -r '
  .abi[] |
  select(
    .type == "function" and 
    .stateMutability == "view" and 
    (.inputs | length == 0) and 
    (.outputs | length == 1) and
    (.outputs[0] | .name == "" and .type == "bytes32" and .internalType == "bytes32")
  ) |
  .name
')
for abi_role in $abi_roles; do
    hash=$(cast keccak "$abi_role" | awk '{print $1}')
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
    logs_cast=$(cast logs --rpc-url "$rpcUrl" --from-block 0 --to-block latest "$event" --address "$usdnProtocolAddress" -j)
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
            topics=$(printf "$log" | jq -r '.topics')
            
            # Add first topic to the log
            log=$(printf "$log" | jq --arg new_topic "$event" '.topics[0] = $new_topic')

            # Other topics
            first_topic=$(printf "$log" | jq -r '.topics[0]')
            second_topic=$(printf "$topics" | jq -r '.[1]')
            third_topic=$(printf "$topics" | jq -r '.[2]')
            fourth_topic=$(printf "$topics" | jq -r '.[3]')


            # Replace the second topic with the associated string and add it to the log
            new_second_topic=${abi_roles_map[$second_topic]}
            log=$(printf "$log" | jq --arg new_topic "$new_second_topic" '.topics[1] = $new_topic')

            # Replace the third and fourth topics instead of the hash with the associated role or address and add it to the log
            if [[ "$first_topic" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
                role=${abi_roles_map[$third_topic]}
                log=$(printf "$log" | jq --arg new_topic "$role" '.topics[2] = $new_topic')

                role=${abi_roles_map[$fourth_topic]}
                log=$(printf "$log" | jq --arg new_topic "$role" '.topics[3] = $new_topic')
                
            elif [ "$first_topic" == "RoleGranted(bytes32,address,address)" ] || [ "$first_topic" == "RoleRevoked(bytes32,address,address)" ]; then
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

# JSON output

# Ask the user if they want to save to a file or display on screen
printf "Do you want to save the JSON to a file (y), display it on the screen (d), or do nothing (n)? "
read -r choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    # Save the JSON to a file
    output_file="roles.json"
    printf "%s" "$json_output" | jq . > "$output_file"
    printf "JSON saved to file: %s\n" "$output_file"
elif [[ "$choice" == "d" || "$choice" == "D" ]]; then 
    # Display the JSON on the screen
    printf "%s" "$json_output" | jq .
fi


# CSV output

# Ask the user if they want to save to a file or display on screen
printf "Do you want to save the CSV to a file (y), display it on the screen (d), or do nothing (n)? "
read -r csv_choice
csv_output+=$(printf "$json_output" | jq -r '.[] | [.Role, .Role_admin, (.Addresses | join(","))] | @csv')
if [[ "$csv_choice" == "y" || "$csv_choice" == "Y" ]]; then
    # Save the CSV to a file
    output_file="roles.csv"
    printf "Role,Role_admin,Addresses\n" > "$output_file"
    printf "%s" "$csv_output" >> "$output_file"
    printf "CSV saved to file: %s\n" "$output_file"
elif [[ "$choice" == "d" || "$choice" == "D" ]]; then 
    # Display the CSV on the screen
    printf "%s\n" "Role,Role_admin,Addresses"
    printf "%s\n" "$csv_output"
fi