#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

BROADCAST="broadcast/00_DeployUsdn.s.sol/1/run-latest.json"
ledger=false
rpcUrl=""
deployerPrivateKey=""
address=""

read -p $'\n'"Enter rpc url : " userRpcUrl
rpcUrl=$userRpcUrl

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        read -p $'\n'"Enter deployer address : " deployerAddress
        address=$deployerAddress

        printf "\n\n$green Running script in Ledger mode with :\n"
        ledger=true
        break
        ;;
    [Nn]*)
        read -s -p $'\n'"Enter private key : " privateKey
        deployerPrivateKey=$privateKey

        address="$(cast wallet address $deployerPrivateKey)"
        if [[ -z $address ]]; then
            printf "\n$red The private key is invalid$nc\n\n"
            exit 1
        fi

        printf "\n\n$green Running script in Non-Ledger mode with :\n"
        ledger=false
        break
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

while true; do
    printf "\n$blue Address :$nc $address"
    printf "\n$blue RPC URL :$nc "$rpcUrl"\n"
    read -p $'\n'"Do you wish to continue? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        export DEPLOYER_ADDRESS=$address
        break
        ;;
    [Nn]*)
        exit 1
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

if [ $ledger = true ]; then
    forge script -l -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --broadcast
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --broadcast
fi

status=$?
if [ $status -ne 0 ]; then
    echo "Failed to deploy USDN contract"
    exit 1
fi

printf "$green USDN contract have been deployed !\n"
printf " Waiting for confirmation... (12s) $nc\n"
sleep 12s

for i in {1..15}; do
    printf "$green Trying to fetch USDN address... (attempt $i/15)$nc\n"
    USDN_ADDRESS="$(cat "$BROADCAST" | jq -r '.returns.Usdn_.value')"
    usdnCode="$(cast code "$USDN_ADDRESS")"

    if [[ ! -z $usdnCode ]]; then
        printf "\n$green USDN contract found on blockchain$nc\n\n"
        export USDN_ADDRESS="$USDN_ADDRESS"
        break
    fi

    sleep 2s
done

if [ $ledger = true ]; then
    forge script -l -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast
fi

popd >/dev/null
