# README

Assuming you have Echidna installed

`npm run echidna` to launch echidna with npm

# Invariants being Tested

## Protocol tests

| Test name | Description                                                  | Status         |
| --------- | ------------------------------------------------------------ | -------------- |
| PROTCL-0  | Initiates a deposit of WSTETH and SDEX to the USDN Protocol. | Unknown revert |
| PROTCL-1  | Initiates a withdrawal of USDN shares.                       | Unknown revert |
| PROTCL-2  | Initiates a long position with WSTETH.                       | Unknown revert |
| PROTCL-3  | Initiates the closing of a WSTETH long position.             | Unknown revert |
| PROTCL-4  | Validates a deposit of WSTETH and SDX.                       | Unknown revert |
| PROTCL-5  | Validates a withdrawal of USDN shares.                       | Unknown revert |
| PROTCL-6  | Validate a long position with WSTETH.                        | Unknown revert |
| PROTCL-7  | Validate a WSTETH long position closing.                     | Unknown revert |
| PROTCL-8  | Validates pending actions.                                   | Unknown revert |
| PROTCL-9  | Initiate and validate a deposit action without test.         | Passing        |
| PROTCL-10 | Initiate and validate a withdrawal action without test.      | Passing        |
| PROTCL-11 | Initiate and validate a long action without test.            | Passing        |
| PROTCL-12 | Initiate and validate a close action without test.           | Passing        |
| PROTCL-13 | Initialize USDN protocol.                                    | Unknown revert |

## Rebalancer tests

| Test name | Description                                               | Status         |
| --------- | --------------------------------------------------------- | -------------- |
| RBLCR-0   | Initiates a deposit of WSTETH and SDEX to the Rebalancer. | Unknown revert |

## Admin tests

| Test name | Description | Result |
| --------- | ----------- | ------ |

## Protocol invariants

| Invariant name | Description                                   | Status  |
| -------------- | --------------------------------------------- | ------- |
| PROTCL-0-a     | Balance of X should be equal to balance of Y. | Passing |
| PROTCL-1-c     | Balance of X should be equal to balance of Y. | Fail    |

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
