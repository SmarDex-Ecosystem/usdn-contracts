#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

read -p $'\n'"Entrez l'adresse du contrat : " contractAddress
if [[ -z "$contractAddress" ]]; then
    printf "\n$red L'adresse du contrat est requise.$nc\n"
    exit 1
fi

read -p $'\n'"Entrez l'URL RPC : " rpcUrl
if [[ -z "$rpcUrl" ]]; then
    printf "\n$red L'URL RPC est requise.$nc\n"
    exit 1
fi

declare -a events=(
    "RoleGranted(bytes32,address,address)"
    "RoleRevoked(bytes32,address,address)"
    "RoleAdminChanged(bytes32,bytes32,bytes32)"
)

declare -A topic_map=(
    ["0x0000000000000000000000000000000000000000000000000000000000000000"]="DEFAULT_ADMIN_ROLE"
    ["0x112a81abbbc0a642a71c01ee707237745fdf9150a36cd6c341a77a82b042fcfe"]="SET_EXTERNAL_ROLE"
    ["0x02f5b57e73f7374270c293a6c0f8f21b963fcb794517ca371178f1ebf3e0ea7d"]="CRITICAL_FUNCTIONS_ROLE"
    ["0xa33d215b27d5ec861579769ea5343a0a14da1a34a49b09fa343facf13bf852ba"]="SET_PROTOCOL_PARAMS_ROLE"
    ["0x2332b7708e4d211430c3d07e50a5483bc31f86f1a3c7c79e159a5bab63060e82"]="SET_USDN_PARAMS_ROLE"
    ["0x5fdbe07c81484705bc90cbf005feb2ecc66822288a5ac5d3cf89e384fa6fdd47"]="SET_OPTIONS_ROLE"
    ["0x233d5d22cfc2df30a1764cac21e2207537a3711647f2c29fe3702201f65c1444"]="PROXY_UPGRADE_ROLE"
    ["0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a"]="PAUSER_ROLE"
    ["0x427da25fe773164f88948d3e215c94b6554e2ed5e5f203a821c9f2f6131cf75a"]="UNPAUSER_ROLE"
    ["0xe066b764dbc472e706cbc2f8733ab0fcee541dd01136dc6512dca8f6dc61b692"]="ADMIN_SET_EXTERNAL_ROLE"
    ["0xe7b4cf829186f8c4eae56184e8b39efd89f053da9890202c466f766239b5c06d"]="ADMIN_CRITICAL_FUNCTIONS_ROLE"
    ["0x668144e07fd661d09cc13a56f823a5cecc9ddd81fac15e0f66a794e2048f7eeb"]="ADMIN_SET_PROTOCOL_PARAMS_ROLE"
    ["0x750ec48621e602bf6e87efd3f05aacefc0afaaf02ef76bf2316cd7d61322e136"]="ADMIN_SET_USDN_PARAMS_ROLE"
    ["0x98de2855152060acaf991c6c67bcd523513322d493b38e46544cf92e3fee8334"]="ADMIN_SET_OPTIONS_ROLE"
    ["0x5afc0553d94a015add162f99e64d9f1e7954cb5168d8eb6c93ee26a783968d8a"]="ADMIN_PROXY_UPGRADE_ROLE"
    ["0x365fccb66c62533ad1447fec73f7b764cf03ac69d512070f7c0aa889025cec19"]="ADMIN_PAUSER_ROLE"
    ["0xe7747964bba14b1d51bb4f84f826a6ba3ef37d424902280c5a01c99b837c970d"]="ADMIN_UNPAUSER_ROLE"
)

# Array to store logs
declare -a logs=()

contractAddress="0x59891a8f6a60fA55053Aff265b95B1264Cd0fc69"
rpcUrl="127.0.0.1:8545"

# Loop over each event to fetch logs
for event in "${events[@]}"; do
    printf "\n$blue Fetching logs for event:$nc $event\n"

    # Run cast to get logs for each event and capture output in log_output variable
    log_output=$(cast logs --rpc-url "$rpcUrl" --from-block 0 --to-block latest "$event" --address "$contractAddress" -j)
    status=$?

    # Check if the command executed successfully
    if [ $status -ne 0 ]; then
        printf "\n$red Failed to retrieve logs for event:$nc $event\n"
    else
        printf "\n$green Logs fetched successfully for event:$nc $event\n"
        # Filter the output to only include topics and blockNumber using jq
        filtered_output=$(printf "$log_output" | jq -c '.[] | {topics: .topics, blockNumber: .blockNumber}')

        # Process each filtered output
        for entry in $filtered_output; do
            # Extract the topics array
            topics=$(printf "$entry" | jq -r '.topics')
            
            # First topic
            entry=$(printf "$entry" | jq --arg new_topic "$event" '.topics[0] = $new_topic')

            # Second topic
            second_topic=$(printf "$topics" | jq -r '.[1]')
            # Replace the second topic with the associated string
            if [[ -n "${topic_map[$second_topic]}" ]]; then
                new_second_topic=${topic_map[$second_topic]}
                # Replace in the JSON entry
                entry=$(printf "$entry" | jq --arg new_topic "$new_second_topic" '.topics[1] = $new_topic')
            fi

            # Use jq to extract the first topic for comparison
            first_topic=$(printf "$entry" | jq -r '.topics[0]')
            if [[ "$first_topic" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
                # Third topic
                third_topic=$(printf "$topics" | jq -r '.[2]')
                if [[ -n "${topic_map[$third_topic]}" ]]; then
                    new_third_topic=${topic_map[$third_topic]}
                    # Replace in the JSON entry
                    entry=$(printf "$entry" | jq --arg new_topic "$new_third_topic" '.topics[2] = $new_topic')
                fi  

                # Fourth topic
                fourth_topic=$(printf "$topics" | jq -r '.[3]')
                if [[ -n "${topic_map[$fourth_topic]}" ]]; then
                    new_fourth_topic=${topic_map[$fourth_topic]}
                    # Replace in the JSON entry
                    entry=$(printf "$entry" | jq --arg new_topic "$new_fourth_topic" '.topics[3] = $new_topic')
                fi  
                
            else
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


            # Append the modified entry to the logs array
            # printf "\n$blue Logs:$nc $entry\n"
            logs+=("$entry")
        done
    fi
done

Print all filtered logs at the end
printf "\n$green All event logs (filtered):$nc\n"
for log in "${logs[@]}"; do
    printf "%s\n" "$log"
done

printf "\n$green Event logs retrieval completed.$nc\n"


declare -A roles
declare -A admin_roles
declare -a addresses=()

for log in "${logs[@]}"; do
    event=$(printf "$log" | jq -r '.topics[0]')
    role=$(printf "$log" | jq -r '.topics[1]')
    address=$(printf "$log" | jq -r '.topics[2]')
    new_admin_role=$(printf "$log" | jq -r '.topics[3]')

    if [[ "$event" == "RoleGranted(bytes32,address,address)" ]]; then
        roles["$role"]+="$address "
        addresses+=("$address")
    elif [[ "$event" == "RoleAdminChanged(bytes32,bytes32,bytes32)" ]]; then
        admin_roles["$role"]="$new_admin_role"
    fi
done

printf "Roles et Adresses:"
for role in "${!roles[@]}"; do
    printf "Role: $role \n"
    printf "Addresses: ${roles[$role]} \n"
    printf "Role_admin: ${new_admin_roles[$role]} \n"
    echo "-----------------------"
done

printf "Liste d'adresses uniques:"
printf '%s\n' "${addresses[@]}" | sort -u