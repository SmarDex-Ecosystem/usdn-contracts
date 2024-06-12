# <h1 align="center">Ultimate Synthetic Delta Neutral - USDN</h1>

[![Main workflow](https://github.com/Blockchain-RA2-Tech/usdn-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/Blockchain-RA2-Tech/usdn-contracts/actions/workflows/ci.yml)
[![Release Workflow](https://github.com/Blockchain-RA2-Tech/usdn-contracts/actions/workflows/release.yml/badge.svg)](https://github.com/Blockchain-RA2-Tech/usdn-contracts/actions/workflows/release.yml)

## Installation

### Foundry

To install Foundry, run the following commands in your terminal:

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

### Dependencies

To install existing dependencies, run the following commands:

```bash
forge install
npm install
```

The `forge install` command is only used to add the forge standard library. Other dependencies should be managed with
npm.

In order to add a new dependency, use the `npm i [packagename]` command with any package from the
[npm registry](https://www.npmjs.com/).

For instance, to add the latest [OpenZeppelin library](https://github.com/OpenZeppelin/openzeppelin-contracts):

```bash
npm i @openzeppelin/contracts
```

### Nix

If using [`nix`](https://nixos.org/), the repository provides a development shell in the form of a flake.

The devshell can be activated with the `nix develop` command.

To automatically activate the dev shell when opening the workspace, install [`direnv`](https://direnv.net/)
(available on nixpkgs) and run the following command inside this folder:

```console
$ direnv allow
```

The environment provides the following tools:

- load `.env` file as environment variables
- foundry
- solc v0.8.25
- slither
- Node 18

## Usage

### Tests

Compile the test utils by running the following inside the `test_utils` folder:

```bash
cargo build --release
```

This requires some dependencies to build (the `m4` lib notably). Using the provided nix devShell should provide
everything.

To run tests, use `forge test -vvv` or `npm run test`.

### Snapshots

The CI checks that there was no unintended regression in gas usage. To do so, it relies on the `.gas-snapshot` file
which records gas usage for all tests. When tests have changed, a new snapshot should be generated with the
`npm run snapshot` command and commited to the repo.

### Deployment scripts

Deployment for anvil forks should be done with a custom bash script at `script/deployFork.sh` which can be run without
arguments. It must set up any environment variable required by the foundry deployment script.

Common arguments to `forge script` are described in
[the documentation](https://book.getfoundry.sh/reference/forge/forge-script#forge-script).

Notably, the `--rpc-url` argument allows to choose which RPC will receive the transactions. The available shorthand
names are defined in [`foundry.toml`](https://github.com/petra-foundation/foundry-template/blob/master/foundry.toml),
(e.g. `mainnet`, `goerli`) and use URLs defined as environment variables (see `.env.example`).

## Foundry Documentation

For comprehensive details on Foundry, refer to the [Foundry book](https://book.getfoundry.sh/).

### Helpful Resources

- [Forge Cheat Codes](https://book.getfoundry.sh/cheatcodes/)
- [Forge Commands](https://book.getfoundry.sh/reference/forge/)
- [Cast Commands](https://book.getfoundry.sh/reference/cast/)

## Code Standards and Tools

### Forge Formatter

Foundry comes with a built-in code formatter that we configured like this (default values were omitted):

```toml
[profile.default.fmt]
line_length = 120 # Max line length
bracket_spacing = true # Spacing the brackets in the code
wrap_comments = true # use max line length for comments as well
number_underscore = "thousands" # add underscore separators in large numbers
```

### Husky

The pre-commit configuration for Husky runs `forge fmt --check` to check the code formatting before each commit. It also
checks the gas snapshot and prevents committing if it has changed.

In order to setup the git pre-commit hook, run `npm install`.

### Slither

Slither is integrated into a GitHub workflow and runs on every push to the master branch.
