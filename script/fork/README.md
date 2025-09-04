# USDN Fork Deployment Stack

This folder contains scripts and utilities to deploy the USDN protocol on a local Ethereum fork for testing and development.

## 📋 Overview

The fork stack allows you to:
- Quickly deploy the complete USDN protocol on a local environment
- Test functionality with mocked oracles
- Simulate specific market conditions
- Develop and debug without real gas costs

## 🏗️ Architecture

### Main Scripts

1. **`ForkCore.s.sol`** - Abstract base contract
   - Manages mocked oracle configuration
   - Sets up roles and permissions
   - Initializes starting prices

2. **`DeployUsdnFork.s.sol`** - USDN-only deployment
   - Deploys USDN protocol with wstETH as collateral
   - Inherits from `ForkCore` and `DeployUsdnWstethUsd`

3. **`DeployShortdnFork.s.sol`** - Shortdn-only deployment
   - Deploys Shortdn protocol with wUSDN as collateral

4. **`DeployUsdnAndShortdnFork.s.sol`** - Complete deployment
   - Deploys both protocols (USDN + Shortdn)
   - Returns a struct with all deployed contracts

### Shell Scripts

- **`deployUsdnFork.sh`** - Bash script to deploy USDN only
- **`deployUsdnAndShortdnFork.sh`** - Bash script to deploy USDN + Shortdn

## 🚀 Usage Guide

### Prerequisites

1. **Anvil** running:
```bash
anvil --rpc-url "https://eth-mainnet.g.alchemy.com/v2/ZMTGh2wcbFIUDheXaKBN7cFHBfccH-RT"
```

2. **Environment variables** (optional):
```bash
cp example.env .env
# Edit .env according to your needs
```

### Available Environment Variables

```bash
# Starting price for USDN (default: 3000 ETH)
START_PRICE_USDN=3000

# Starting price for Shortdn (default: 1 ETH)
START_PRICE_SHORTDN=1

# Custom addresses (optional)
UNDERLYING_ADDRESS_WSTETH=0x...
UNDERLYING_ADDRESS_WUSDN=0x...
```

### USDN-only Deployment

```bash
# From the fork folder
./deployUsdnFork.sh

# Or from the project root
./script/fork/deployUsdnFork.sh
```

This script:
1. Deploys the complete USDN protocol
2. Configures mocked oracles
3. Extracts deployed contract addresses
4. Generates a `.env.usdn` file with all addresses

### USDN + Shortdn Deployment

```bash
# From the fork folder
./deployUsdnAndShortdnFork.sh

# Or from the project root
./script/fork/deployUsdnAndShortdnFork.sh
```

This script deploys both protocols and generates `.env.usdn_shortdn`.

### Manual Deployment with Forge

Make sure to define `$rpcUrl` and `$deployerPrivateKey`.

```bash
# USDN only
forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" \
  ./script/fork/DeployUsdnFork.s.sol:DeployUsdnFork \
  --broadcast --force

# USDN + Shortdn
forge script --non-interactive --private-key $deployerPrivateKey -f "$rpcUrl" \
  ./script/fork/DeployUsdnAndShortdnFork.s.sol:DeployUsdnAndShortdnFork \
  --broadcast --force
```

## 📁 Generated Files

After deployment, the following variables are casted:

```bash
Fork environment variables:
SDEX_TOKEN_ADDRESS=0x...
WSTETH_TOKEN_ADDRESS=0x...
WSTETH_ORACLE_MIDDLEWARE_ADDRESS=0x...
LIQUIDATION_REWARDS_MANAGER_WSTETH_ADDRESS=0x...
REBALANCER_USDN_ADDRESS=0x...
USDN_TOKEN_ADDRESS=0x...
WUSDN_TOKEN_ADDRESS=0x...
USDN_PROTOCOL_USDN_ADDRESS=0x...
WUSDN_TO_ETH_ORACLE_MIDDLEWARE_ADDRESS=0x...
LIQUIDATION_REWARDS_MANAGER_WUSDN_ADDRESS=0x...
REBALANCER_SHORTDN_ADDRESS=0x...
USDN_NO_REBASE_SHORTDN_ADDRESS=0x...
USDN_PROTOCOL_SHORTDN_ADDRESS=0x...
USDN_TOKEN_BIRTH_BLOCK=23288509
USDN_TOKEN_BIRTH_TIME=1756973939
```

## 🔧 Advanced Configuration

### Mocked Oracles

The scripts use mocked oracles for:
- **wstETH/USD**: Configurable price via `START_PRICE_USDN`
- **wUSDN/ETH**: Configurable price via `START_PRICE_SHORTDN`
- **ETH/USD**: Uses a mocked oracle middleware

### Roles and Permissions

All admin roles are automatically granted to the deployer address:
- `ADMIN_SET_EXTERNAL_ROLE`
- `ADMIN_SET_OPTIONS_ROLE`
- `ADMIN_SET_PROTOCOL_PARAMS_ROLE`
- `ADMIN_SET_USDN_PARAMS_ROLE`
- `ADMIN_CRITICAL_FUNCTIONS_ROLE`
- And all corresponding execution roles

## 🧪 Testing and Development

### Interacting with Contracts

```bash
# Example: mint USDN
cast send $USDN_PROTOCOL_USDN_ADDRESS "mint(uint256)" 1000000000000000000 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8545
```

## 🛠️ Troubleshooting

### Common Issues

1. **Anvil not started**
   ```bash
   Error: failed to get chain id for http://localhost:8545
   ```
   → Check that Anvil is running

2. **Environment variables not found**
   → Make sure the `.env` file is in the correct directory

3. **Deployment failure**
   → Verify that the private key and RPC URL are correct

### Environment Reset

```bash
# Restart Anvil
pkill anvil
anvil --rpc-url "https://eth-mainnet.g.alchemy.com/v2/ZMTGh2wcbFIUDheXaKBN7cFHBfccH-RT"

# Remove cache files
rm -rf broadcast/ cache/
```

## 📚 Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [Anvil Documentation](https://book.getfoundry.sh/anvil/)
