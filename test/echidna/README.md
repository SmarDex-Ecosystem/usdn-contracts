# Quickstart

Assuming you have Echidna installed

`npm run echidna` to launch echidna with npm

# Invariants being Tested

## Protocol invariants

TODO lastAction doc


| Invariant name | Description                                                        | Status |
|----------------|--------------------------------------------------------------------|--------|
| PROTCL-1       | When initializing an action, the sender pay the security deposit   | x      |
| PROTCL-2       | When initializing an action, the protocol pay the security deposit | x      |


## Vault invariants

| Invariant name | Description                                                                      | Status |
|----------------|----------------------------------------------------------------------------------|--------|
| VAULT-1        | When an user initialize a deposit, msg.sender pay the amount of wstETH defined   | x      |
| VAULT-2        | When an user initialize a deposit, msg.sender pay some SDEX                      | x      |
| VAULT-3        | When an user initialize a deposit, protocol receive the amount of wstETH defined | x      |




## What to do in case of failure?

Tips and tricks:

- Add `export ECHIDNA_SAVE_TRACES=true`, then run Echidna to get full traces for entire length of call sequences ([reference](https://github.com/crytic/echidna/pull/1180))

## Installation Requirements

1. [Slither](https://github.com/crytic/slither/)
2. [Echidna](https://github.com/crytic/echidna)
3. [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Echidna – Locally

```bash
npm run echidna
```

See [./config/echidnaConfig.yaml](config/echidnaConfig.yaml) for yaml config.
