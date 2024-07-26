# Quickstart

Assuming you have Echidna installed

`npm run echidna` to launch echidna with npm

# Invariants being Tested

## Protocol invariants

| Invariant name | Description                                                             | Status |
|----------------|-------------------------------------------------------------------------|--------|
| PROTCL-1       | When initializing an action, the sender should pay the security deposit | x      |

## What to do in case of failure?

Tips and tricks:

- Add `export ECHIDNA_SAVE_TRACES=true`, then run Echidna to get full traces for entire length of callsequences ([reference](https://github.com/crytic/echidna/pull/1180))

## Installation Requirements

1. [Slither](https://github.com/crytic/slither/)
2. [Echidna](https://github.com/crytic/echidna)
3. [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Echidna – Locally

```bash
npm run echidna
```

See [./config/echidnaConfig.yaml](config/echidnaConfig.yaml) for yaml config.
