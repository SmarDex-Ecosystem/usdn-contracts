#!/usr/bin/env bash
# Path of the script folder (so that the script can be invoked from somewhere else than the project's root)
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
# Execute in the context of the project's root
pushd $SCRIPT_DIR/.. >/dev/null

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

USAGE="Usage: $(basename $0) [-r RPC_URL] [-s SAFE_ADDRESS] [-w WUSDN_ADDRESS] (-e GET_WSTETH) (-t HARDWARE_WALLET)"

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

# Asks the user for the deployer's private key and checks if it's valid
# Also calculate the USDN token address
function handlePrivateKey() {
    read -s -p $'\n'"Enter the private key : " privateKey
    deployerPrivateKey=$privateKey
    address=$(cast wallet address $deployerPrivateKey)
    if [[ -z $address ]]; then
        printf "\n$red The private key is invalid$nc\n\n"
        exit 1
    fi
}

# Parses the arguments passed to the script
function parseArguments() {
    while getopts ":r:s:t:w:he" opt; do
        case ${opt} in
        r)
            rpcUrl="$OPTARG"
            ;;
        s)
            safeAddress="$OPTARG"
            export SAFE_ADDRESS=$safeAddress
            ;;
        e)
            getWstETH=true
            ;;
        w)
            wusdnAddress="$OPTARG"
            export WUSDN_ADDRESS=$wusdnAddress
            ;;
        t)
            if [ "$OPTARG" = "ledger" ] || [ "$OPTARG" = "trezor" ]; then
                hardwareWallet=$OPTARG
            else
                printf "$red Invalid hardware wallet option (ledger/trezor): $OPTARG$nc\n"
                exit 1
            fi
            ;;
        h)
            printf "$red $USAGE\n"
            exit 1
            ;;
        :)
            printf "$red Option -${OPTARG} requires an argument\n"
            exit 1
            ;;
        ?)
            printf "$red Invalid option: -${OPTARG}\n"
            exit 1
            ;;
        esac
    done

    if [[ -z "${rpcUrl}" || -z "${safeAddress}" || -z "${wusdnAddress}" ]]; then
        printf "\nError: All -r, -w and -s options are required\n\n"
        printf "${USAGE}\n"
        exit 1
    fi
}

# ---------------------------------------------------------------------------- #
#                                  main script                                 #
# ---------------------------------------------------------------------------- #

requiredDependencies=("forge" "cast" "jq")
checkRequiredDependencies
checkNodeVersion
hardwareWallet=false
getWstETH=false

if [ "$1" = "--test" ]; then
    # for test mode we use the local RPC and the 29th account from anvil
    deployerPrivateKey="0x233c86e887ac435d7f7dc64979d7758d69320906a0d340d2b6518b0fd20aa998"
    rpcUrl="127.0.0.1:8545"
    export DEPLOYER_ADDRESS="0x9DCCe783B6464611f38631e6C851bf441907c710"
    export GET_WSTETH=true
    export SAFE_ADDRESS="0x1E3e1128F6bC2264a19D7a065982696d356879c5"
    export IS_PROD_ENV=true
    export WUSDN_ADDRESS="0x1234567890123456789012345678901234567890"

else
    printf "\n$green To run this script in test mode, add \"-t\" or \"--test\"$nc\n\n"

    parseArguments "$@"

    handlePrivateKey

    while true; do
        printf "\n$blue RPC URL          :$nc $rpcUrl"
        printf "\n$blue Deployer address :$nc $address"
        printf "\n$blue Get wsETH        :$nc $getWstETH"
        printf "\n$blue Safe address     :$nc $safeAddress"
        printf "\n$blue WUSDN address    :$nc $wusdnAddress\n"

        read -p $'\n'"Do you wish to continue? (Yy/Nn) : " yn

        case $yn in
        [Yy]*)
            export IS_PROD_ENV=true
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

if [ "$hardwareWallet" = "ledger" ]; then
    forge script -l -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast --slow
elif [ "$hardwareWallet" = "trezor" ]; then
    forge script -t -f "$rpcUrl" script/01_Deploy.s.sol:Deploy --broadcast --slow
else
    forge script --private-key $deployerPrivateKey -f "$rpcUrl" script/01_DeployProtocol.s.sol:DeployProtocol --broadcast --slow
fi

popd >/dev/null
