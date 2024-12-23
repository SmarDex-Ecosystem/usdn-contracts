# Scripts

## Deploy USDN token

### Production mode

The script verifies that the deployer address has a nonce of 0. It then deploys the token. Finally, it grants the `DEFAULT_ADMIN_ROLE` to the safe address and renounces this role from the deployer.

Use the following command to deploy the USDN token:

```shell
./script/deployUsdnToken.sh -r YOUR_RPC_URL -s SAFE_ADDRESS
```

It will then prompt you to enter the deployer's private key.

Help can be displayed with the `-h` flag.

```shell
./script/deployUsdnToken.sh -h
```

A test mode is available with the `-t` or `--test` flag. It will deploy the token with default values (rpc url: localhost:8545, deployer: 29th account of anvil, safe: EthSafeAddr).

```shell
./script/deployUsdnToken.sh -t
```

### Standalone mode

You can run the forge script directly with the following command:

```shell
forge script --private-key YOUR_PRIVATE_KEY -f YOUR_RPC_URL script/00_DeployUsdn.s.sol:DeployUsdn --broadcast --slow
```

Two environment variables are required: `DEPLOYER_ADDRESS` and `SAFE_ADDRESS`.

## Deploy protocol

### Production mode

For a mainnet deployment, you have to use the shell script. It will prompt you to enter the required environment variables :

- the rpc url
- the initial long amount
- the get wstETH flag
- the private key of the deployer (or public key if you use a ledger/trezor)

```shell
deployMainnet.sh
```

The script can be run with the following command with `-t` or `--test` flag to deploy with default values. (rpc url: localhost:8545, initial long amount: 100 ethers, get wstETH: true, deployer : 29th account of anvil)

### Fork mode

The deployment script for the fork mode does not require any input:

```shell
deployFork.sh
```

### Standalone mode

You can run the forge script directly with the following command:

```shell
forge script script/01_DeployProtocol.s.sol:DeployProtocol -f YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY --broadcast
```

Required environment variables: `INIT_LONG_AMOUNT`, `DEPLOYER_ADDRESS`, `SAFE_ADDRESS` and `IS_PROD_ENV`.

If running on mainnet, remember to deploy the USDN token first with the `00_DeployUSDN.s.sol` script and set the `USDN_ADDRESS` environment variable.

### Environment variables

Environment variables can be used to control the script execution:

- `INIT_LONG_AMOUNT`: amount to use for the `initialize` function call
- `DEPLOYER_ADDRESS`: the address of the deployer
- `USDN_ADDRESS`: required if running `01_Deploy.s.sol` in a production environment (not fork)
- `GET_WSTETH`: whether to get wstETH by sending ether to the wstETH contract or not. Only applicable if `WSTETH_ADDRESS` is given.
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

Example using the real wstETH and depositing 10 ETH for both vault side and long side for mainnet deployment:

```bash
export INIT_LONG_AMOUNT=10000000000000000000
export DEPLOYER_ADDRESS=0x1234567890123456789012345678901234567890
export GET_WSTETH=true
export IS_PROD_ENV=true
```

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
- `block-number`: the block number to start the scan from (optional)

- example:

```bash
./script/utils/scanRoles.sh --protocol 0x0Fd23cC6c13681ddB9ECE2ae0EEAFaf7a534208f --rpc-url https://sepolia.gateway.tenderly.co --block-number 0
```

You need to provide just the protocol address because the script will automatically fetch the other addresses from the protocol. The script will save the results in 1 csv and json file per contract with access control, and 1 csv and json file total for all the contracts with simple ownership.

## Verify contracts

The verifying script will work with a broadcast file, the compiled contracts and an etherscan API key.
You don't need to be the deployer to verify the contracts.
Before verifying, you need to compile the contracts :

```forge compile```

Be sure to be in the same version as the deployment to avoid bytecode difference.
You can then verify by using this cli:

```bash
npm run verify -- PATH_TO_BROADCAST_FILE -e ETHERSCAN_API_KEY
```

To show some extra debug you can add `-d` flag.
If you are verifying contracts in another platform than Etherscan, you can specify the url with `--verifier-url`  
