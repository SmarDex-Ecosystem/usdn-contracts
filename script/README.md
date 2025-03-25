# Scripts

## Deploy protocol

### Production mode

For a mainnet deployment, you can use the `01_DeployUsdnWsteth.s.sol` script with:

```bash
forge clean && forge script -f RPC_URL script/01_DeployUsdnWsteth.s.sol:DeployUsdnWsteth --broadcast -i 1 --batch-size 5
```

You can use `-t` or `-l` options instead of `-i 1` for trezor or ledger hardware wallet. The `forge clean` command is necessary to use the OpenZeppelin verification tool.

### Fork mode

The deployment script for the fork mode does not require any input:

```bash
./script/fork/deployFork.sh
```

#### Set a start price and a custom underlying asset value

You can define `UNDERLYING_ADDRESS` and/or `START_PRICE` env variables.  
If you do so, the `wStEth` asset will be replaced by `UNDERLYING_ADDRESS` and the underlying price will then be defined to `START_PRICE`.

## Upgrade protocol

Each upgrade logic depends on the implementation, so no boilerplate can be used for every upgrade version. This means you need to checkout to the corresponding tag version to see the exact upgrade script used.

Some general rules apply:

- Implement the reinitialization function (ex: `initializeStorageV2`) with the required parameters
  - Make sure it is only callable by the PROXY_UPGRADE_ROLE addresses
  - Make sure it has the `reinitialize` modifier with the correct version
- Add the previous tag of the contract as a dependency in the `foundry.toml` file as well as in the remapping
  - Example: If we deployed tag 0.17.2 and released a new tag 0.17.3, we would need to add 0.17.2 in the `[dependencies]` section,
    like so: `usdn-protocol-previous = { version = "0.17.2", git = "git@github.com:SmarDex-Ecosystem/usdn-contracts.git", tag = "v0.17.2" }`
    and `"usdn-protocol-previous/=dependencies/usdn-protocol-previous-0.17.2/src/"` in the `remappings` variable
  - By doing so, the previous version will be compiled and available for the upgrade script to do a proper validation. You can find the `UsdnProtocolImpl.sol` file at `out/UsdnProtocol/UsdnProtocolImpl.sol/UsdnProtocolImpl.json`
- Change the artifacts' names in `50_Upgrade.s.sol`
  - If needed, change the `opts.referenceContract` option with the correct previous implementation's path
  - If needed, comment the line that re-deploy the fallback contract

If you are ready to upgrade the protocol, then you can launch the bash script `script/upgrade.sh`. It will prompt you to enter a RPC url, the address of the deployed USDN protocol, and a private key. The address derived from the private key must have the `PROXY_UPGRADE_ROLE` role.

## Anvil fork configuration

The `anvil` fork should be launched with at least the following parameters:

- `-a 100` to fund 100 addresses with 10'000 Ξ
- `-f https://..` to fork mainnet at the latest height
- `--chain-id $FORK_CHAIN_ID` to change from the default (1) forked chain ID

```bash
anvil -a 100 -f [Mainnet RPC] --chain-id $FORK_CHAIN_ID
```

## Logs analysis command

This utility gathers all the logs emitted from the deployed contracts and prints them nicely into the console.

The script first requires that the ABIs have been exported with `npm run exportAbi`.

Then, it can be used like so:

```bash
npx tsx script/utils/logsAnalysis.ts -r https://fork-rpc-url.com/ --protocol 0x24EcC5E6EaA700368B8FAC259d3fBD045f695A08 --usdn 0x0D92d35D311E54aB8EEA0394d7E773Fc5144491a --middleware 0x4278C5d322aB92F1D876Dd7Bd9b44d1748b88af2
```

The parameters are the RPC URL and the deployed addresses of the 3 main contracts.

## Functions clashes

This utility checks that two contracts don't have a common function selector.
We can specify common base contracts to filter wanted duplications with the `-c` flag.

It can be used like so:

```bash
npx tsx script/utils/functionClashes.ts UsdnProtocolImpl UsdnProtocolFallback -c AccessControlDefaultAdminRulesUpgradeable PausableUpgradeable
```

## Scan Roles

This bash script will scan the blockchain to get the roles of the UsdnProtocol / Usdn / OracleMiddleware and the owner of the LiquidationRewardsManager / Rebalancer contracts.
Then, it will generate files containing the addresses assigned to all the relevant roles and contracts.

you need to run the script with the following arguments:

- `rpc-url`: the RPC URL of the network you want to scan
- `protocol`: the address of the deployed USDN protocol
- `long-farming`: the address of the deployed LongFarming contract
- `block-number`: the block number to start the scan from (optional)

- example:

```bash
./script/utils/scanRoles.sh --protocol 0x656cB8C6d154Aad29d8771384089be5B5141f01a --rpc-url https://mainnet.gateway.tenderly.co --long-farming 0xF9D36078A248AF249AA57ae1D5D0c1033d6Bbe27
```

You need to provide just the protocol address because the script will automatically fetch the other addresses from the protocol. The script will save the results in 1 csv and json file per contract with access control, and 1 csv and json file total for all the contracts with simple ownership.

## Verify contracts

The verifying script will work with a broadcast file, the compiled contracts and an etherscan API key.
You don't need to be the deployer to verify the contracts.
Before verifying, you need to compile the contracts :

`forge compile`

Be sure to be in the same version as the deployment to avoid bytecode difference.
You can then verify by using this cli:

```bash
npm run verify -- PATH_TO_BROADCAST_FILE -e ETHERSCAN_API_KEY
```

To show some extra debug you can add `-d` flag.
If you are verifying contracts in another platform than Etherscan, you can specify the url with `--verifier-url`

## Build initialization transaction for Gnosis Safe

This script is used to build the initialization transaction for the Gnosis Safe:

```bash
npm run exportAbi && npx tsx script/utils/initTxBuilder.ts -r RPC_URL -t INITIAL_TOTAL_AMOUNT
```

## Deploy setRebaseHandlerManager

Run this command to deploy the SetRebaseHandlerManager contract (your private key will be prompted):

```bash
forge script -l -f RPC_URL script/54_DeploySetRebaseHandlerManager.sol:DeploySetRebaseHandlerManager --broadcast
```

## Set Current Parameters for a New Protocol

This script is meant to be used on a fork. To transfer all current USDN protocol, Rebalancer an liquidation rewards manager parameters to a new protocol, run the `SetProtocolParams` script with:

```bash
forge script -f RPC_URL script/utils/SetProtocolParams.s.sol --unlocked --broadcast
```

You will be prompted to enter the new protocol address. Note that all setter roles will be granted to the default admin.
