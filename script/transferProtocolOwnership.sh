#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

# Check NodeJS version
node_version=$(node -v)
node_version=$((${node_version:1:2})) # Remove the "V", the minor version and then convert to integer
if [ $node_version -lt 20 ]; then
    printf "\n$red NodeJS version is lower than 20 (it is $node_version), please update it$nc\n"
    exit 1
fi

read -p $'\n'"Enter the RPC URL : " userRpcUrl
rpcUrl="$userRpcUrl"

read -p $'\n'"Enter the protocol address : " userProtocolAddress
protocolAddress="$userProtocolAddress"

adminAddress=$(cast call -r $rpcUrl $protocolAddress "defaultAdmin()")
adminAddress=$(cast parse-bytes32-address $adminAddress)
if [[ -z $adminAddress ]]; then
    printf "\n$red Failed to fetch admin address, values are not correct$nc\n\n"
    printf "RPC URL : $rpcUrl\n"
    printf "Protocol address : $protocolAddress\n\n"
    exit 1
else
    printf "\n$green Admin address fetched successfully$nc : $adminAddress\n"
fi

read -p $'\n'"Enter the new owner address : " userNewOwner
newOwner="$userNewOwner"

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        printf "\n\n$green Running script in Ledger mode with :\n"
        ledger=true

        break
        ;;
    [Nn]*)
        read -s -p $'\n'"Enter the private key : " privateKey
        ownerPrivateKey=$privateKey

        address=$(cast wallet address $ownerPrivateKey)
        if [[ $address != $adminAddress ]]; then
            printf "\n$red The private key is not the owner of the protocol$nc\n"
            exit 1
        fi

        printf "\n\n$green Running script in Non-Ledger mode with :\n"

        break
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

while true; do
    printf "\n$blue Protocol address :$nc $protocolAddress"
    printf "\n$blue Admin address :$nc $adminAddress"
    printf "\n$blue New owner address :$nc $newOwner"
    printf "\n$blue RPC URL :$nc "$rpcUrl"\n"
    read -p $'\n'"Do you wish to continue? (Yy/Nn) : " yn

    case $yn in
    [Yy]*)
        export USDN_PROTOCOL_ADDRESS=$protocolAddress
        export NEW_OWNER_ADDRESS=$newOwner
        break
        ;;
    [Nn]*)
        exit 1
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

if [[ $ledger == true ]]; then
    forge script -l -f "$rpcUrl" script/03_TransferProtocolOwnership.s.sol:TransferProtocolOwnership --broadcast
else
    forge script --private-key $ownerPrivateKey -f "$rpcUrl" script/03_TransferProtocolOwnership.s.sol:TransferProtocolOwnership --broadcast
fi

status=$?
if [ $status -ne 0 ]; then
    echo "Failed to change admin address"
    exit 1
fi

printf "$green Admin address changed !\n"

for i in {1..15}; do
    printf "$green Trying to fetch new owner... (attempt $i/15)$nc\n"
    adminAddress=$(cast call -r $rpcUrl $protocolAddress "defaultAdmin()")

    if [[ ! -z $adminAddress ]]; then
        printf "\n$green Change of ownership is confirmed$nc\n\n"
        export USDN_ADDRESS=$USDN_ADDRESS
        break
    fi

    if [ $i -eq 15 ]; then
        printf "\n$red Failed to fetch the new owner$nc\n\n"
        exit 1
    fi

    sleep 10s
done

popd >/dev/null
