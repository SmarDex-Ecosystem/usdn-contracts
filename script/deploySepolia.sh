#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

ledger=false
broadcastMode=""
rpcUrl=""
deployerPrivateKey=""

read -p $'\n'"Enter rpc url : " userRpcUrl
rpcUrl=$userRpcUrl

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        read -p $'\n'"Enter address : " address

        printf "\n$green Running script in Ledger mode with :\n"
        printf "\n$blue Address :$nc $address\n"
        printf "$blue RPC URL :$nc $rpcUrl\n"
        ledger=true
        export DEPLOYER_ADDRESS=$address
        break
        ;;
    [Nn]*)

        read -s -p $'\n'"Enter private key : " privateKey
        deployerPrivateKey=$privateKey

        address=$(cast wallet address $deployerPrivateKey)
        if [[ -z $address ]]; then
            printf "\n$red The private key is invalid$nc\n\n"
            exit 1
        fi

        printf "\n$green Running script in Non-Ledger mode with :\n"
        printf "\n$blue Address :$nc $address"
        printf "\n$blue RPC URL :$nc $rpcUrl\n"
        ledger=false
        break
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

while true; do
    read -p $'\n'"Do you wish to broadcast? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        broadcastMode="--broadcast"
        break
        ;;
    [Nn]*)
        break
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

if [ $ledger = true ]; then
    forge script -l -f $rpcUrl script/01_Deploy.s.sol:Deploy $broadcastMode
else
    forge script --private-key $deployerPrivateKey -f $rpcUrl script/01_Deploy.s.sol:Deploy $broadcastMode
fi
