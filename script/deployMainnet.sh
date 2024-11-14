#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

broadcastPath="broadcast/00_DeployUsdn.s.sol/"
broadcastFile="/run-latest.json"

# --------------------------------- functions -------------------------------- #

# Checks if the required dependencies are installed
function checkRequiredDependencies() {
    for dep in "${requiredDependencies[@]}"; do
        if ! command -v $dep &>/dev/null; then
            printf "\n$red $dep is required but it's not installed. Please install it and try again$nc\n"
            exit 1
        fi
    done
}

# Checks if the NodeJS version is greater than 20
function checkNodeVersion() {
    node_version=$(node -v)
    node_version=$((${node_version:1:2})) # Remove the "V", the minor version and then convert to integer
    if [ "$node_version" -lt 20 ]; then
        printf "\n$red NodeJS version is lower than 20 (it is $node_version), please update it$nc\n"
        exit 1
    fi
}

# Asks the user if he wants to mint wsETH during the deployment and handles the input
function handleWstETH() {
    while true; do
        read -p $'\n'"Do you want to mint wsETH during the deployment ? (yY/nN) : " yn
        case $yn in
        [Yy]*)
            getWstETH=true
            break
            ;;
        [Nn]*)
            getWstETH=false
            break
            ;;
        *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
        esac
    done
}

# Asks the user if he wants to use a hardware wallet or a private key
# to deploy the contracts and handles the input
function handleKeys() {
    while true; do
        read -p $'\n'"Do you wish to use a hardware wallet? (trezor/ledger/nN) : " yn
        case $yn in
        "ledger"*)
            read -p $'\n'"Enter the deployer address : " deployerAddress
            address=$deployerAddress
            printf "\n\n$green Running script in Ledger mode with :\n"
            hardwareWallet="ledger"
            break
            ;;
        "trezor"*)
            read -p $'\n'"Enter the deployer address : " deployerAddress
            address=$deployerAddress
            printf "\n\n$green Running script in Trezor mode with :\n"
            hardwareWallet="trezor"
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
        *) printf "\nPlease answer trezor, ledger or no (N/n).\n" ;;
        esac
    done
}

# Deploys the USDN token contract and exports the address
function deployUsdn() {
    if [ "$hardwareWallet" = "ledger" ]; then
        forge script -l -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --broadcast --slow
    elif [ "$hardwareWallet" = "trezor" ]; then
        forge script -t -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --broadcast --slow
    else
        forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/00_DeployUsdn.s.sol:DeployUsdn --broadcast --slow
    fi

    # Check if the deployment was successful by checking the return code of the previous command
    if [ "$?" -ne 0 ]; then
        echo "Failed to deploy USDN contract"
        exit 1
    fi

    chainId=$(cast chain-id -r "$rpcUrl")
    broadcast="$broadcastPath""$chainId""$broadcastFile"

    # Wait for the USDN contract to be mined, and export the address
    for i in {1..15}; do
        printf "$green Trying to fetch USDN address... (attempt $i/15)$nc\n"
        USDN_ADDRESS="$(cat $broadcast | jq -r '.returns.Usdn_.value')"
        usdnCode=$(cast code -r "$rpcUrl" "$USDN_ADDRESS")

        if [[ ! -z $usdnCode ]]; then
            printf "\n$green USDN contract found on blockchain$nc\n\n"
            export USDN_ADDRESS=$USDN_ADDRESS
            return
        fi

        sleep 10s
    done
    printf "\n$red Failed to fetch USDN address$nc\n\n"
    exit 1
}

# ---------------------------------------------------------------------------- #
#                                  main script                                 #
# ---------------------------------------------------------------------------- #

requiredDependencies=("forge" "cast" "jq")
checkRequiredDependencies
checkNodeVersion
hardwareWallet=false
getWstETH=false

if [ "$1" = "-t" ] || [ "$1" = "--test" ]; then
    # for test mode we use the local RPC and the 29th account from anvil
    deployerPrivateKey="0x233c86e887ac435d7f7dc64979d7758d69320906a0d340d2b6518b0fd20aa998"
    rpcUrl="127.0.0.1:8545"
    export DEPLOYER_ADDRESS="0x9DCCe783B6464611f38631e6C851bf441907c710"
    export INIT_LONG_AMOUNT="100000000000000000000"
    export GET_WSTETH=true

else
    printf "\n$green To run this script in test mode, add \"-t\" or \"--test\"$nc\n"

    read -p $'\n'"Enter the RPC URL : " userRpcUrl
    rpcUrl="$userRpcUrl"
    read -p $'\n'"Enter the initial long amount : " userLongAmount
    initialLongAmount="$userLongAmount"

    handleWstETH
    handleKeys

    while true; do
        printf "\n$blue RPC URL     :$nc $rpcUrl"
        printf "\n$blue Address     :$nc $address"
        printf "\n$blue Long amount :$nc "$(cast from-wei $initialLongAmount)" ether"
        printf "\n$blue Get wsETH   :$nc $getWstETH\n"

        read -p $'\n'"Do you wish to continue? (Yy/Nn) : " yn

        case $yn in
        [Yy]*)
            export DEPLOYER_ADDRESS=$address
            export INIT_LONG_AMOUNT=$initialLongAmount
            if [ "$getWstETH" = true ]; then
                export GET_WSTETH=true
            fi
            break
            ;;
        [Nn]*)
            exit 1
            ;;
        *) printf "\nPlease answer yes (Y/y) or no (N/n).\n" ;;
        esac
    done
fi

deployUsdn

if [ "$hardwareWallet" = "ledger" ]; then
    forge script -l -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast --slow
elif [ "$hardwareWallet" = "trezor" ]; then
    forge script -t -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast --slow
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/01_DeployProtocol.s.sol:DeployProtocol --broadcast --slow
fi

popd >/dev/null
