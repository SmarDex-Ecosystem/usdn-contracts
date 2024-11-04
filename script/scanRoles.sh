#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

# Loop to get and validate the protocol address
while true; do
    read -p $'\n'"Enter the USDN Protocol's address: " usdnProtocolAddress
    usdnProtocolAddress=$(echo "$usdnProtocolAddress" | xargs)
    if [[ -z "$usdnProtocolAddress" ]]; then
        printf "\n${red}The contract address is required.${nc}\n"
    else
        printf "\n${blue}Address :${nc} $usdnProtocolAddress\n"
        break
    fi
done

# Loop to get and validate the RPC URL
while true; do
    read -p $'\n'"Enter the RPC URL: " rpcUrl
    rpcUrl=$(echo "$rpcUrl" | xargs)
    if [[ -z "$rpcUrl" ]]; then
        printf "\n${red}The RPC URL is required.${nc}\n"
    else
        printf "\n${blue}RPC URL :${nc} $rpcUrl\n"
        break
    fi
done


# Events in IAccessControl.sol from OpenZeppelin
declare -a events=(
    "RoleGranted(bytes32,address,address)"
    "RoleRevoked(bytes32,address,address)"
    "RoleAdminChanged(bytes32,bytes32,bytes32)"
)

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

echo "Roles scanned on abi:"
for key in "${!abi_roles_map[@]}"; do
    echo "Hash: $key, Role: ${abi_roles_map[$key]}"
done

# Extract and sort logs for each event

declare -a logs=()
# Loop over each event to fetch logs
for event in "${events[@]}"; do
    printf "\n$blue Fetching logs for event:$nc $event\n"

    # Run cast to get logs for each event and capture output in log_output variable
    log_output=$(cast logs --rpc-url "$rpcUrl" --from-block 0 --to-block latest "$event" --address "$usdnProtocolAddress" -j)
    status=$?

    # Check if the command executed successfully
    if [ $status -ne 0 ]; then
        printf "\n$red Failed to retrieve logs for event:$nc $event\n"
    else
        printf "\n$green Logs fetched successfully for event:$nc $event\n"
        # Filter the output to only include topics, blockNumber and logIndex using jq
        filtered_output=$(printf "$log_output" | jq -c '.[] | {topics: .topics, blockNumber: .blockNumber, logIndex: .logIndex}')

        # Process each filtered output
        for entry in $filtered_output; do
            # Extract the topics array
            topics=$(printf "$entry" | jq -r '.topics')
            
            # First topic
            entry=$(printf "$entry" | jq --arg new_topic "$event" '.topics[0] = $new_topic')

            # Second topic
            second_topic=$(printf "$topics" | jq -r '.[1]')
            # Replace the second topic with the associated string
            if [[ -n "${abi_roles_map[$second_topic]}" ]]; then
                new_second_topic=${abi_roles_map[$second_topic]}
                # Replace in the JSON entry
                entry=$(printf "$entry" | jq --arg new_topic "$new_second_topic" '.topics[1] = $new_topic')
            fi

            # First topic
            first_topic=$(printf "$entry" | jq -r '.topics[0]')

            if [[ "$first_topic" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
                # Third topic
                third_topic=$(printf "$topics" | jq -r '.[2]')
                if [[ -n "${abi_roles_map[$third_topic]}" ]]; then
                    new_third_topic=${abi_roles_map[$third_topic]}
                    # Replace in the JSON entry
                    entry=$(printf "$entry" | jq --arg new_topic "$new_third_topic" '.topics[2] = $new_topic')
                fi  

                # Fourth topic
                fourth_topic=$(printf "$topics" | jq -r '.[3]')
                if [[ -n "${abi_roles_map[$fourth_topic]}" ]]; then
                    new_fourth_topic=${abi_roles_map[$fourth_topic]}
                    # Replace in the JSON entry
                    entry=$(printf "$entry" | jq --arg new_topic "$new_fourth_topic" '.topics[3] = $new_topic')
                fi  
                
            elif [ "$first_topic" == "RoleGranted(bytes32,address,address)" ] || [ "$first_topic" == "RoleRevoked(bytes32,address,address)" ]; then
                # Third topic
                third_topic=$(printf "$topics" | jq -r '.[2]')
                if [[ -n "$third_topic" ]]; then
                    address=$(cast parse-bytes32-address "$third_topic")
                    entry=$(printf "$entry" | jq --arg new_topic "$address" '.topics[2] = $new_topic')
                fi

                # Fourth topic
                fourth_topic=$(printf "$topics" | jq -r '.[3]')
                if [[ -n "$fourth_topic" ]]; then
                    address=$(cast parse-bytes32-address "$fourth_topic")
                    entry=$(printf "$entry" | jq --arg new_topic "$address" '.topics[3] = $new_topic')
                fi
            fi

            # Convert blockNumber from hex to decimal and replace the blockNumber in the entry
            block_number=$(printf "$entry" | jq -r '.blockNumber')
            decimal_block_number=$((block_number))
            entry=$(printf "$entry" | jq --argjson new_block_number "$decimal_block_number" '.blockNumber = $new_block_number')

            # Convert logIndex from hex to decimal and replace the logIndex in the entry
            log_index=$(printf "$entry" | jq -r '.logIndex')
            decimal_log_index=$((log_index))
            entry=$(printf "$entry" | jq --argjson new_log_index "$decimal_log_index" '.logIndex = $new_log_index')


            # Append the modified entry to the logs array
            logs+=("$entry")
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