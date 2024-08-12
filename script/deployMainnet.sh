#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'
ledger=false

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        printf "\n$green In Ledger mode, please connect your ledger and set URL_ETH_MAINNET the .env file before using this script. $nc\n\n"
        if [[ -z $URL_ETH_MAINNET ]]; then
            printf "\n$red URL_ETH_MAINNET is not set or it holds an empty string $nc\n\n"
            exit 1
        fi

        ledger=true
        break
        ;;
    [Nn]*)
        printf "\n$green In Non-Ledger mode, please set DEPLOYER_PRIVATE_KEY and URL_ETH_MAINNET in the .env file before using this script.$nc\n\n"

        if [[ -z $DEPLOYER_PRIVATE_KEY ]]; then
            printf "\n$red DEPLOYER_PRIVATE_KEY is not set or it holds an empty string $nc\n\n"
            exit 1
        fi
        if [[ -z $URL_ETH_MAINNET ]]; then
            printf "\n$red URL_ETH_MAINNET is not set or it holds an empty string $nc\n\n"
            exit 1
        fi

        ledger=false
        break
        ;;
    *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
    esac
done

if [ $ledger = true ]; then
    forge script -l --non-interactive -f $URL_ETH_MAINNET script/00_DeployUsdn.s.sol:DeployUsdn --broadcast
else
    forge script --private-key $DEPLOYER_PRIVATE_KEY -f $URL_ETH_MAINNET script/00_DeployUsdn.s.sol:DeployUsdn --broadcast
fi

status=$?
if [ $status -ne 0 ]; then
    echo "Failed to deploy USDN contract"
    exit 1
fi

printf "$green Waiting for USDN contract to be deployed... (12s) $nc\n"
sleep 12s

BROADCAST="broadcast/00_DeployUsdn.s.sol/1/run-latest.json"
export USDN_ADDRESS=$(cat "$BROADCAST" | jq -r '.returns.Usdn_.value')

if [ $ledger = true ]; then
    forge script -l --non-interactive -f $URL_ETH_MAINNET script/01_Deploy.s.sol:Deploy --broadcast
else
    forge script --non-interactive --private-key $DEPLOYER_PRIVATE_KEY -f $URL_ETH_MAINNET script/01_Deploy.s.sol:Deploy --broadcast
fi
