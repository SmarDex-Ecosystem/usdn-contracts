<img align="right" width="150" height="150" top="100" src="https://github.com/foundry-rs/.github/blob/main/profile/logo.png">

# <h1 align="center"> Real Estate Executive - Foundry Template</h1>

**Welcome to the template repository, specifically designed to help you create new Foundry projects quickly while
Adhering to Real Estate Executive's standards.**

![Github Actions](https://github.com/petra-foundation/foundry-template/workflows/CI/badge.svg)

## How to Get Started

Click "Use this template" on [GitHub](https://github.com/petra-foundation/foundry-template) to create a new repository
with this repo as the initial state.

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
- solc v0.8.20
- slither
- GNU make
- Node 18

## Usage

### Tests

To run tests, use the `forge test -vvv` command or `make test`.

### Deployment scripts

Each deployment script should be added as a command calling `forge script` in the `Makefile`, passing the appropriate
arguments, and then called with `make <command>`.

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
line_length = 120 # Max line lenght
bracket_spacing = true # Spacing the brakets in the code
wrap_comments = true # use max line length for comments aswell
```

### Husky

The pre-commit configuration for Husky runs `forge fmt --check` to check the code formatting before each commit.

In order to setup the git pre-commit hook, run `npm install`.

### Slither

Slither is integrated into a GitHub workflow and runs on every push to the master branch.

## Future work

### Tests skeleton generation

[Bulloak](https://github.com/alexfertel/bulloak)
