# Deployments

## Set parameters

Environment variables can be used to control the script execution:

- `FORK_CHAIN_ID`: the chain ID of the anvil fork. If deploying on mainnet (production), this variable can be omitted.
- `DEPLOYER_ADDRESS`: required, the address that is used for simulating the transactions on the network fork (needs to have a sufficient balance).
- `FEE_COLLECTOR` : required, the receiver of all protocol fees
- `SDEX_ADDRESS`: if provided, skips deployment of the mock SDEX token
- `WSTETH_ADDRESS`: if provided, skips deployment of the mock wstETH token
- `MIDDLEWARE_ADDRESS`: if provided, skips deployment of the oracle middleware
- `PYTH_ADDRESS`: required if middleware address not provided, the contract address of the pyth oracle
- `PYTH_WSTETH_PRICE_ID`: required if middleware address not provided, the price id of the wstETH pyth oracle
- `PYTH_STETH_PRICE_ID`: required if middleware address not provided, the price id of the wstETH pyth oracle
- `CHAINLINK_ETH_PRICE_ADDRESS`: required if middleware address not provided, the address of the stETH chainlink oracle
- `CHAINLINK_ETH_PRICE_VALIDITY`: the amount of time (in seconds) we consider the price valid. A tolerance should be added to avoid reverting if chainlink misses the heartbeat by a few minutes
- `LIQUIDATION_REWARDS_MANAGER_ADDRESS`: if provided, skips deployment of the liquidation rewards manager
- `REBALANCER_ADDRESS`: if provided, skips deployment of the rebalancer
- `CHAINLINK_GAS_PRICE_ADDRESS`: required if liquidation rewards manager address not provided, the address of the gas price chainlink oracle
- `CHAINLINK_GAS_PRICE_VALIDITY`: the amount of time (in seconds) we consider the price valid. A tolerance should be added to avoid reverting if chainlink misses the heartbeat by a few minutes
- `USDN_ADDRESS`: if provided, skips deployment of the USDN token
- `INIT_DEPOSIT_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).
- `INIT_LONG_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).
- `INIT_LONG_LIQPRICE`: desired liquidation price for the initial long position. For fork deployment, this value is
  ignored and the price is calculated to get a leverage of ~2x.
- `GET_WSTETH`: whether to get wstETH by sending ether to the wstETH contract or not. Only applicable if `WSTETH_ADDRESS` is given.

Example using the real wstETH and depositing 1 ETH for both vault side and long side (with liquidation
at 1 USD so a leverage close to 1x):
Will also link oracles to mainnet instances:

```
export FORK_CHAIN_ID=31337
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export FEE_COLLECTOR=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export SDEX_ADDRESS=0x5de8ab7e27f6e7a1fff3e5b337584aa43961beef
export WSTETH_ADDRESS=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export INIT_DEPOSIT_AMOUNT=1000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000
export INIT_LONG_LIQPRICE=1000000000000000000
export PYTH_ADDRESS=0x4305FB66699C3B2702D4d05CF36551390A4c69C6
export PYTH_WSTETH_PRICE_ID=0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784
export PYTH_STETH_PRICE_ID=0x846ae1bdb6300b817cee5fdee2a6da192775030db5615b94a465f53bd40850b5
export CHAINLINK_ETH_PRICE_ADDRESS=0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8
export CHAINLINK_ETH_PRICE_VALIDITY=3720
export CHAINLINK_GAS_PRICE_ADDRESS=0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C
export CHAINLINK_GAS_PRICE_VALIDITY=7500
export GET_WSTETH=true
```

## Deploy protocol

Initializing the contract (when `INIT_DEPOSIT_AMOUNT` and `INIT_LONG_AMOUNT` are defined) requires enough wstETH to make
the deposit and open the long position.

If `WSTETH_ADDRESS` is defined and `GET_WSTETH=true`, then the script will wrap some ether before initializing the
contract so that there is enough balance.

```
forge script --non-interactive --private-key 0xac... -f http://localhost:8545 script/Deploy.s.sol:Deploy --broadcast
```

## Anvil fork configuration

The `anvil` fork should be launched with at least the following parameters:

- `-a 100` to fund 100 addresses with 10'000 Ξ
- `-f https://..` to fork mainnet at the latest height
- `--chain-id $FORK_CHAIN_ID` to change from the default (1) forked chain ID
- `--code-size-limit 50000` to support larger contracts (50kB) since we are still in the process of optimizing code size

```
anvil -a 100 -f [Mainnet RPC] --chain-id $FORK_CHAIN_ID --code-size-limit 50000
```

## Logs analysis command

This utility gathers all the logs emitted from the deployed contracts and prints them nicely into the console.

The script first requires that the ABIs have been exported with `npm run exportAbi`.

Then, it can be used like so:

```
npx ts-node script/logsAnalysis.ts -r https://fork-rpc-url.com/ --protocol 0x24EcC5E6EaA700368B8FAC259d3fBD045f695A08 --usdn 0x0D92d35D311E54aB8EEA0394d7E773Fc5144491a --middleware 0x4278C5d322aB92F1D876Dd7Bd9b44d1748b88af2
```

The parameters are the RPC URL and the deployed addresses of the 3 main contracts.
