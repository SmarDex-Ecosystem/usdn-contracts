# Quickstart 

Assuming you have Medusa and Echidna installed, it should be as easy as 

`npm run echidna` to launch echidna with npm

# Invariants being Tested

## Stateful tests

| Test name      | Description                                                             | Status |
|---------|-------------------------------------------------------------------------|--------|
| initiateDeposit  | Initiates a deposit of WSTETH and SDEX to the USDN Protocol.             | Unknown revert |
| initiateWithdrawal  | Initiates a withdrawal of USDN shares.                   | Unknown revert |
| initiateOpenPosition  | Initiates a long position with WSTETH.       | Unknown revert |
| initiateClosePosition  | Close a long position with WSTETH. | Unknown revert |
| validateDeposit  | Validates a deposit of WSTETH and SDX.                   | Unknown revert |
| validateWithdrawal  | Validates a withdrawal of USDN shares.               | Unknown revert |
| validateOpenPosition  | Validate a long position with WSTETH.      | Unknown revert |
| validateClosePosition  | Validate a WSTETH long position closing.                | Unknown revert |
| validatePendingActions  | Validates pending actions.              | Unknown revert |

## Admin tests
| Test name       | Description                                                                                                            | Result |
|----------|------------------------------------------------------------------------------------------------------------------------|--------|

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

See [./test/echidna/config/echidnaConfig.yaml](./test/echidna/config/echidnaConfig.yaml) for yaml config.
