# Deployments

## Set parameters

Environment variables can be used to control the script execution:

- `DEPLOYER_ADDRESS`: required, the address that is used for simulating the transactions on the network fork (needs to have a sufficient balance).
- `WSTETH_ADDRESS`: if provided, skips deployment of the mock wstETH token
- `MIDDLEWARE_ADDRESS`: if provided, skips deployment of the oracle middleware
- `PYTH_ADDRESS`: required if middleware address not provided, the contract address of the pyth oracle
- `PYTH_WSTETH_PRICE_ID`: required if middleware address not provided, the price id of the wstETH pyth oracle
- `CHAINLINK_STETH_PRICE_ADDRESS`: required if middleware address not provided, the address of the stETH chainlink oracle
- `USDN_ADDRESS`: if provided, skips deployment of the USDN token
- `INIT_DEPOSIT_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).
- `INIT_LONG_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).
- `GET_WSTETH`: whether to get wstETH by sending ether to the wstETH contract or not. Only applicable if `WSTETH_ADDRESS` is given.

Example for an anvil fork using the real wstETH and depositing 1 ETH for both vault side and long side:
Will also link oracles to the real mainnet configuration:

```
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export WSTETH_ADDRESS=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export INIT_DEPOSIT_AMOUNT=1000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000
export PYTH_ADDRESS=0x4305FB66699C3B2702D4d05CF36551390A4c69C6
export PYTH_WSTETH_PRICE_ID=0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784
export CHAINLINK_STETH_PRICE_ADDRESS=0xcfe54b5cd566ab89272946f602d76ea879cab4a8
export GET_WSTETH=true
```

## Deploy protocol

Initializing the contract (when `INIT_DEPOSIT_AMOUNT` and `INIT_LONG_AMOUNT` are defined) requires enough wstETH to make
the deposit and open the long position.

If `WSTETH_ADDRESS` is defined and `GET_WSTETH=true`, then the script will wrap some ether before initializing the
contract so that there is enough balance.

```
forge script --via-ir --non-interactive --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -f anvil script/Deploy.s.sol --broadcast
```
