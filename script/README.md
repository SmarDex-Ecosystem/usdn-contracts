# Scripts

## Deploy protocol

Just run the bash script corresponding to the desired deployment (mainnet or fork).

You will be prompted to enter the `RPC_URL` of the network you want to deploy to. If you are deploying with a Ledger, you will also be prompted for the deployer address. And without a Ledger, you will be prompted for the deployer private key.  
The deployment script for the fork mode does not require any input.

Only one env variables is required : `INIT_LONG_AMOUNT`.
The initial deposit amount will be calculated from `INIT_LONG_AMOUNT` with a leverage of 2x.

If `GET_WSTETH=true`, then the script will wrap some ether before initializing the
contract so that there is enough balance.

```
./script/deployMainnet.sh
./script/deployFork.sh
```

Environment variables can be used to control the script execution:

#### Required

- `INIT_DEPOSIT_AMOUNT`: amount to use for the `initialize` function call
- `INIT_LONG_AMOUNT`: amount to use for the `initialize` function call

#### Optional

- `DEPLOYER_ADDRESS`: required only for fork deployment, the address of the deployer
- `FEE_COLLECTOR`: the receiver of all protocol fees (set to `DEPLOYER_ADDRESS` if not set in the environment)
- `SDEX_ADDRESS`: if provided, skips deployment of the SDEX token
- `WSTETH_ADDRESS`: if provided, skips deployment of the wstETH token
- `MIDDLEWARE_ADDRESS`: if provided, skips deployment of the oracle middleware
- `PYTH_ADDRESS`: the contract address of the pyth oracle
- `PYTH_ETH_FEED_ID`: the price ID of the ETH pyth oracle
- `REDSTONE_ETH_FEED_ID`: the feed ID of the ETH Redstone oracle
- `CHAINLINK_ETH_PRICE_ADDRESS`: the address of the ETH chainlink oracle
- `CHAINLINK_ETH_PRICE_VALIDITY`: the amount of time (in seconds) we consider the price valid. A tolerance should be added to avoid reverting if chainlink misses the heartbeat by a few minutes
- `LIQUIDATION_REWARDS_MANAGER_ADDRESS`: if provided, skips deployment of the liquidation rewards manager
- `REBALANCER_ADDRESS`: if provided, skips deployment of the rebalancer
- `CHAINLINK_GAS_PRICE_VALIDITY`: the amount of time (in seconds) we consider the price valid. A tolerance should be added to avoid reverting if chainlink misses the heartbeat by a few minutes
- `USDN_ADDRESS`: required if running `01_Deploy.s.sol` in a production environment (not fork)
- `GET_WSTETH`: whether to get wstETH by sending ether to the wstETH contract or not. Only applicable if `WSTETH_ADDRESS` is given.

Example using the real wstETH and depositing 10 ETH for both vault side and long side for mainnet deployment (with liquidation
at 1 USD so a leverage close to 1x):

```
export INIT_DEPOSIT_AMOUNT=10000000000000000000
export INIT_LONG_AMOUNT=10000000000000000000
export GET_WSTETH=true
```

## Upgrade protocol

Before you launch the upgrade script, there are a few things you need to do:

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

## Transfer ownership

This bash script will prompt you to enter an RPC url, the protocol address, the new owner address and a private key. The address derived from the private key must have the `DEFAULT_ADMIN_ROLE` role.

```bash
./script/transferProtocolOwnership.sh
```

If you want to run the script with foundry directly, in a standalone mode, you need to make sure that required environment variable is set:

- `NEW_OWNER_ADDRESS`: the address of the new owner
- `USDN_PROTOCOL_ADDRESS`: the address of the deployed USDN protocol

```solidity
forge script script/03_TransferProtocolOwnership.s.sol -f YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY --broadcast
```

## Anvil fork configuration

The `anvil` fork should be launched with at least the following parameters:

- `-a 100` to fund 100 addresses with 10'000 Ξ
- `-f https://..` to fork mainnet at the latest height
- `--chain-id $FORK_CHAIN_ID` to change from the default (1) forked chain ID

```
anvil -a 100 -f [Mainnet RPC] --chain-id $FORK_CHAIN_ID
```

## Logs analysis command

This utility gathers all the logs emitted from the deployed contracts and prints them nicely into the console.

The script first requires that the ABIs have been exported with `npm run exportAbi`.

Then, it can be used like so:

```
npx tsx script/utils/logsAnalysis.ts -r https://fork-rpc-url.com/ --protocol 0x24EcC5E6EaA700368B8FAC259d3fBD045f695A08 --usdn 0x0D92d35D311E54aB8EEA0394d7E773Fc5144491a --middleware 0x4278C5d322aB92F1D876Dd7Bd9b44d1748b88af2
```

The parameters are the RPC URL and the deployed addresses of the 3 main contracts.

## Functions clashes

This utility checks that two contracts don't have a common function selector.
We can specify a common base contract to filter wanted duplications with the `-s` flag.

It can be used like so:

```
npx tsx script/utils/functionClashes.ts UsdnProtocolImpl.sol UsdnProtocolFallback.sol -s UsdnProtocolStorage.sol
```

## Scan Roles

This bash script will scan the roles of the UsdnProtocol / Usdn / OracleMiddleware and scan the owner of the LiquidationRewardsManager / Rebalancer

you need to run the script with the following arguments:

- `rpc-url`: the RPC URL of the network you want to scan
- `protocol`: the address of the deployed USDN protocol
- `block-number`: the blockNumber to start the scan from (optional)

- example:

```bash
./script/utils/scanRoles.sh --protocol 0x0Fd23cC6c13681ddB9ECE2ae0EEAFaf7a534208f --rpc-url https://sepolia.gateway.tenderly.co --block-number 0
```

You need to provide just the protocol address because the script will automatically fetch the other addresses from the protocol. The script will save the results in 4 csv and 4 json files.
