#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

broadcast="broadcast/00_DeployUsdn.s.sol/1/run-latest.json"
ledger=false

read -p $'\n'"Enter the RPC URL : " userRpcUrl
rpcUrl="$userRpcUrl"

while true; do
    read -p $'\n'"Do you wish to use a ledger? (Yy/Nn) : " yn
    case $yn in
    [Yy]*)
        read -p $'\n'"Enter the deployer address : " deployerAddress
        address=$deployerAddress

        printf "\n\n$green Running script in Ledger mode with :\n"
        ledger=true

        break
        ;;
    [Nn]*)
        read -s -p $'\n'"Enter the private key : " privateKey
        deployerPrivateKey=$privateKey

        address=$(cast wallet address $deployerPrivateKey)
        if [[ -z $address ]]; then
            printf "\n$red The private key is invalid$nc\n\n"
            exit 1
        fi

        printf "\n\n$green Running script in Non-Ledger mode with :\n"

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

read -p $'\n'"Enter the Etherscan api key : " userEtherscanApiKey
etherscanApiKey="$userEtherscanApiKey"

read -p $'\n'"Enter the verifier url : " userVerifierUrl
verifierUrl="$userVerifierUrl"

if [ $ledger = true ]; then
    forge script -l -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --verify --resume --slow --etherscan-api-key $etherscanApiKey --verifier_url $verifierUrl
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --verify --resume --slow --etherscan-api-key $etherscanApiKey --verifier_url $verifierUrl
fi

if [ $ledger = true ]; then
    forge script -l -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --verify --resume --slow --etherscan-api-key $etherscanApiKey --verifier_url $verifierUrl
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --verify --resume --slow --etherscan-api-key $etherscanApiKey --verifier_url $verifierUrl
fi

popd >/dev/null
