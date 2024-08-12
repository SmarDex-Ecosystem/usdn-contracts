#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'
ledger=false
broadcastMode=""

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        printf "\n$green In Ledger mode, please connect your ledger and set URL_SEPOLIA the .env file before using this script. $nc\n\n"
        if [[ -z $URL_SEPOLIA ]]; then
            printf "\n$red URL_SEPOLIA is not set or it holds an empty string $nc\n\n"
            exit 1
        fi

        ledger=true
        break
        ;;
    [Nn]*)
        printf "\n$green In Non-Ledger mode, please set DEPLOYER_PRIVATE_KEY and URL_SEPOLIA in the .env file before using this script.$nc\n\n"

        if [[ -z $DEPLOYER_PRIVATE_KEY ]]; then
            printf "\n$red DEPLOYER_PRIVATE_KEY is not set or it holds an empty string $nc\n\n"
            exit 1
        fi
        if [[ -z $URL_SEPOLIA ]]; then
            printf "\n$red URL_SEPOLIA is not set or it holds an empty string $nc\n\n"
            exit 1
        fi

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
    forge script -l -f $URL_SEPOLIA script/01_Deploy.s.sol:Deploy $broadcastMode
else
    forge script --private-key $DEPLOYER_PRIVATE_KEY -f $URL_SEPOLIA script/01_Deploy.s.sol:Deploy $broadcastMode
fi
