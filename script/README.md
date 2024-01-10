# Deployments

## Set parameters

Environment variables can be used to control the script execution:

- `DEPLOYER_ADDRESS`: required, the address that is used for simulating the transactions on the network fork (needs to have a sufficient balance).
- `WSTETH_ADDRESS`: if provided, skips deployment of the mock wstETH token
- `MIDDLEWARE_ADDRESS`: if provided, skips deployment of the oracle middleware
- `USDN_ADDRESS`: if provided, skips deployment of the USDN token
- `INIT_DEPOSIT_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).
- `INIT_LONG_AMOUNT`: amount to use for the `initialize` function call (if not provided, then initialization is skipped).

Example for an anvil fork using the real wstETH and depositing 1 ETH for both vault side and long side:

```
export DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export WSTETH_ADDRESS=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
export INIT_DEPOSIT_AMOUNT=1000000000000000000
export INIT_LONG_AMOUNT=1000000000000000000
```

## Setup Fork

Get some wstETH. Requires enough ETH to mint the wstETH for the initial deposit and long position.

The private key is the default first user for anvil (funded with 10k ETH)

```
forge script --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -f anvil --via-ir script/Fork.s.sol --broadcast
```

## Deploy protocol

Requires enough wstETH to make the deposit and open the long position + ETH for gas.

```
forge script --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -f anvil --via-ir script/Deploy.s.sol --broadcast
```
