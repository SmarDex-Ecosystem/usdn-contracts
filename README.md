# <h1 align="center">Ultimate Synthetic Delta Neutral - USDN</h1>

[![Main workflow](https://github.com/SmarDex-Ecosystem/usdn-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/SmarDex-Ecosystem/usdn-contracts/actions/workflows/ci.yml)
[![Release Workflow](https://github.com/SmarDex-Ecosystem/usdn-contracts/actions/workflows/release.yml/badge.svg)](https://github.com/SmarDex-Ecosystem/usdn-contracts/actions/workflows/release.yml)

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
forge soldeer install
npm install
```

The `forge soldeer install` command is only used to add libraries for the smart contracts. Other dependencies should be managed with
npm.

In order to add a new dependency, use the `forge soldeer install [packagename]~[version]` command with any package from the
[soldeer registry](https://soldeer.xyz/).

For instance, to add [OpenZeppelin library](https://github.com/OpenZeppelin/openzeppelin-contracts) version 5.0.2:

```bash
forge soldeer install @openzeppelin-contracts~5.0.2
```

The last step is to update the remappings array in the `foundry.toml` config file.

You must have `Node.js` >= 20 installed.

### Nix

If using [`nix`](https://nixos.org/), the repository provides a development shell in the form of a flake.

The devshell can be activated with the `nix develop` command.

To automatically activate the dev shell when opening the workspace, install [`direnv`](https://direnv.net/)
(available on nixpkgs) and run the following command inside this folder:

```console
direnv allow
```

The environment provides the following tools:

- load `.env` file as environment variables
- foundry
- solc v0.8.26
- lcov
- Node 20 + Typescript
- Rust toolchain
- just
- mdbook
- trufflehog
- typist (with gyre-fonts)
- `test_utils` dependencies

## Usage

### Tests

Compile the test utils by running the following command at the root of the repo:

```bash
cargo build --release
```

This requires some dependencies to build (the `m4` lib notably). Using the provided nix devShell should provide
everything.

To run tests, use `forge test -vvv` or `npm run test`.

### Deployment scripts

Deployment for anvil forks should be done with a custom bash script at `script/fork/deployFork.sh` which can be run without
arguments. It must set up any environment variable required by the foundry deployment script.

Deployment for mainnet should be done with a custom bash script at `script/deployMainnet.sh`. To know which variables are required, run the following command:

```bash
script/deployMainnet.sh --help
```

All information about the script can be found in the `script/` folder's README.

### Docker Anvil Fork

You can deploy the contracts to an anvil fork using docker. The following commands will build the docker image and run the deployment script.

```bash
docker build -t usdn-anvil .
docker run --rm -it -p 8545:8545 usdn-anvil script/deployFork.sh
```

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
checks for any private key in the codebase with [trufflehog](https://github.com/trufflesecurity/trufflehog).

In order to setup the git pre-commit hook, run `npm install`.

## Contributors

Implemented by [Stéphane Ballmer](https://github.com/sballmer),
[Lilyan Bastien](https://github.com/lilyanB),
[Valentin Bersier](https://github.com/beeb),
[Yoan Capron](https://github.com/fireboss777),
[Sami Darnaud](https://github.com/samooyo),
[Nicolas Decosterd](https://github.com/KirienzoEth),
[Léo Fasano](https://github.com/Yashiru),
[Alfred Gaillard](https://github.com/blablalf),
[Paul-Alexandre Tessier](https://github.com/Paulalex85)
