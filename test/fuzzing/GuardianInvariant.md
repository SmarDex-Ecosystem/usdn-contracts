# Smardex USDN Fuzzing Suite

## Table of Contents

1. [Overview](#overview)
2. [Contents](#contents)
   - [Summary](#summary)
   - [Core Testing Architecture](#core-testing-architecture)
     - [State Management System](#state-management-system)
     - [Key Components](#key-components-in-a-state-capture)
3. [Protocol Invariant Coverage](#protocol-invariant-coverage)
   - [Core Coverage Areas](#core-coverage-areas)
     - [Position Management](#position-management-posopniposopnv)
     - [Position Closing](#position-closing-posclosiposclosv)
     - [Deposit/Withdrawal Flows](#depositwithdrawal-flows-depidepvwithiwithv)
     - [Action Management](#action-management-pendactv)
     - [Global Protocol Safety](#global-protocol-safety-glob)
4. [Advanced Testing Features](#advanced-testing-features)
   - [Error Management](#error-management)
   - [Complex Scenario Testing](#complex-scenario-testing)
   - [Price Management System](#price-management-system)
5. [Future Roadmap](#future-roadmap)
   - [Current Stage](#current-stage-1-of-3)
   - [Stage 2: Unrestricted Execution](#stage-2-unrestricted-execution)
   - [Stage 3: Production Simulation](#stage-3-production-simulation)
6. [Setup](#setup)
7. [Scope](#scope)
8. [Detailed Documentation](#detailed-documentation)
   - [Invariants Trees](#invariants-trees)
   - [Fuzzing Suite Structure](#fuzzing-suite-tree)
   - [Suite Invariants Table](#suite-invariants-table)

# Overview

Smardex team engaged Guardian for an in-depth security review of their USDN protocol. This comprehensive evaluation, conducted from September 30th to November 4th, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors in various protocol states. This suite, an integral part of the audit, was created during the review period and successfully delivered upon the audit's conclusion.

# Contents

## Summary

This fuzzing suite implements 174 cases tested in 56 invariants and 37 distinct protocol parameters. The suite implements sophisticated property-based testing for the USDN Protocol, with particular focus on complex state transitions and economic invariants.

## Core Testing Architecture

### State Management System

The fuzzing suite employs a custom BeforeAfter.sol state capture framework that provides granular visibility into protocol state transitions through dual-state snapshots (pre and post action). This framework serves as the foundation for comprehensive invariant testing by tracking critical protocol parameters across multiple dimensions while maintaining atomic state comparisons for all protocol operations.

### Key components in a state capture

**Account States**: Tracks balances (ETH, USDN shares, WstETH, SDEX) and pending actions for each account, enabling precise monitoring of user-level state changes.

**Position Management**: Monitors liquidation ticks, profits, exposures, and leverage ratios through parameters like latestLiquidatedTick, positionProfit, and tradingExpo.

**Protocol Economics**: Captures core financial metrics including security deposits, total supply, vault balances, protocol fees, and funding rates.

**Liquidation States**: Tracks liquidation flags, rewards, and pending liquidations through parameters like positionsLiquidatable and liquidationRewards.

**Action Tracking**: Maintains counters for pending actions, cross-user operations, and protocol trigger states to ensure proper action sequencing and validation.

# Protocol Invariant Coverage

The fuzzing suite implements a comprehensive suite of invariants ensuring safety and correctness across all core operations. These invariants are continuously verified through the state management system and fuzzing framework.

### Position Management (POSOPNI/POSOPNV)

Position management invariants ensure safe state transitions during position operations:

- Maintains strict balance accounting during position opening/validation
- Enforces security deposit requirements and fee collection rules
- Verifies ETH and wstETH balance transitions

### Position Closing (POSCLOSI/POSCLOSV)

Position closing invariants protect the closing process:

- Validates position closure state transitions
- Ensures correct liquidation reward distribution
- Maintains protocol/user balance reconciliation
- Enforces proper validator authorization

### Deposit/Withdrawal Flows (DEPI/DEPV/WITHI/WITHV)

Deposit and withdrawal invariants secure fund movements:

- Guarantees accurate share calculations
- Validates all collateral movements
- Maintains protocol balance consistency
- Enforces proper fee collection

### Action Management (PENDACTV)

Pending action invariants maintain system coordination:

- Tracks action validation counts
- Manages security deposit flows
- Validates balance state transitions

### Global Protocol Safety (GLOB)

System-wide invariants ensure overall protocol health:

- Maintains market structure constraints
- Validates protocol fee accounting
- Enforces position leverage limits
- Reconciles total balances

The invariant suite provides comprehensive coverage of all critical protocol operations while maintaining mathematical correctness and economic safety checks.

# Advanced Testing Features

The fuzzing suite implements sophisticated testing mechanisms across several key areas:

1. **Error Management**

   - Comprehensive error catalog spanning 95 distinct error states
   - Granular error classification system including:
     - Deposit and withdrawal processing errors
     - Position management validation failures
     - Oracle integration exceptions
     - Protocol configuration validations
     - Balance and allowance verification errors
   - Systematic error tracking and validation

2. **Complex Scenario Testing**

   - Multi-actor interaction sequences
   - Guided testing flows for complex operations
   - Fee collector verification system
   - Advanced position lifecycle testing

3. **Price Management System**

   - Sophisticated three-mode price control:
     - NORMAL: Standard market price movements
     - ANTI_LIQUIDATION: Price floor protection mechanism
     - SWING: Alternating volatility patterns (10%/3%)

The system provides thorough coverage while maintaining precise control over test conditions and state transitions, enabling comprehensive protocol validation.

## Future Roadmap

## Current Stage (1 of 3)

**Stage 1**: Operating under controlled conditions:

- Minimum transaction threshold: 10,000 wei
- Synchronized oracle updates
- Controlled time progression
- Mocked direct price return
- Enforced one action per call

## Possible improvements (Stages 2 and 3+)

**Stage 2**: Unrestricted Execution

- Dynamic time shifting
- Variable protocol fees
- Variable protocol initialization

**Stage 3**: Production Simulation

- Real-world oracle behavior
- Market stress testing
- Complex multi-action scenarios

## Setup

Please note that this fuzzing suite utilizes cutting-edge feature updates in Echidna, so using the latest release version is essential.

1. Installing Echidna

   Install Echidna, follow the steps here: [Installation Guide](https://github.com/crytic/echidna#installation) using the latest master branch

2. Install libs

```
forge soldeer install
forge install perimetersec/fuzzlib@main --no-commit
chmod u+x test/fuzzing/slither //empty file
```

5. Run Echidna with a Slither check (slow full run)

`echidna test/fuzzing/Fuzz.sol --contract Fuzz --config echidna.yaml`

5. Run Echidna without a Slither check (faster debugging)

`PATH=./test/fuzzing/:$PATH echidna test/fuzzing/Fuzz.sol --contract Fuzz --config echidna.yaml`

## Reproduce with Foundry

`forge test --mp FoundryPlayground.sol --mt test_example`

# Scope

Repo: <https://github.com/GuardianAudits/usdn-fuzzing>

Branch: `main`

Commit: `2430900024983b85bb3edc66d93bdc5910d98b8f`

## Invariants trees

```markdown
# POSOPNI Invariant Trees

## POSOPNI_01 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedOpen
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous + securityDeposit
│ └── !initiatedOpen
│ └── Check: ethBalance = previous - lastAction.securityDepositValue
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous + securityDeposit - lastAction.securityDepositValue

## POSOPNI_02 (User ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedOpen
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous - pythPrice
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous - securityDeposit + lastAction.securityDepositValue - pythPrice
│ └── !initiatedOpen
│ └── Check: ethBalance = previous - pythPrice
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous - securityDeposit + lastAction.securityDepositValue - pythPrice

## POSOPNI_03 (Protocol wstETH Balance Check)

!rebalancerTriggered
├── feeCollectorCallbackTriggered
│ └── Check: Balance = previous + amount - pendingActions - fees - liquidationRewards - positionProfit
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── Check: Balance = previous + amount - pendingActionValue - liquidationRewards - positionProfit
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: Balance = previous + amount - pendingActions - positionProfit

## POSOPNI_04 (User wstETH Balance Check)

!rebalancerTriggered
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── liquidator == user
│ │ └── Check: Balance = previous - amount + liquidationRewards + positionProfit
│ └── liquidator != user
│ └── Check: Balance = previous - amount + positionProfit
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
├── user == lastAction.to
│ └── Check: Balance = previous - amount + positionProfit + pendingActions
└── user != lastAction.to
└── Check: Balance = previous - amount

# POSOPNV Invariant Trees

## POSOPNV_01 (Validator ETH Balance Check)

outcome == Processed && SINGLE_ACTOR_MODE == true
├── validator != user
│ └── Check: ethBalance = previous + securityDeposit + lastAction.securityDepositValue - pythPrice
└── validator == user
└── Check: ethBalance = previous + lastAction.securityDepositValue - pythPrice

## POSOPNV_02 (Protocol ETH Balance Check)

outcome == Processed && SINGLE_ACTOR_MODE == true
└── Check: ethBalance = previous - securityDeposit - lastAction.securityDepositValue

## POSOPNV_03 (Protocol wstETH Balance Check)

├── feeCollectorCallbackTriggered
│ ├── outcome == Liquidated
│ │ ├── liquidator == validator
│ │ │ └── Check: Balance = previous - pendingActions - fees - liquidationRewards - positionProfit
│ │ └── liquidator != validator
│ │ └── Check: Balance = previous - pendingActions - fees - positionProfit
│ └── outcome == Processed
│ └── Check: Balance = previous - pendingActions - fees - positionProfit
└── !feeCollectorCallbackTriggered
├── outcome == Liquidated
│ ├── liquidator == validator
│ │ └── Check: Balance = previous - pendingActions - liquidationRewards - positionProfit
│ └── liquidator != validator
│ └── Check: Balance = previous - pendingActions - positionProfit
└── outcome == Processed
└── Check: Balance = previous - pendingActions - positionProfit

## POSOPNV_04 (Sender wstETH Balance Check)

├── outcome != Liquidated
│ └── liquidator == sender
│ └── Check: wstETHBalance = previous + liquidationRewards
└── outcome == Processed
└── Check: wstETHBalance = previous

# POSCLOSI Invariant Trees

## POSCLOSI_01 (Sender ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── outcome == Liquidated
│ └── Check: ethBalance = previous - pythPrice
└── outcome == Processed
└── Check: ethBalance = previous - securityDeposit - pythPrice

## POSCLOSI_02 (User Pending Action Check)

├── outcome == Liquidated
│ └── Check: pendingAction.action = 0
└── outcome == Processed
└── Check: pendingAction.action = ValidateClosePosition

## POSCLOSI_03 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── outcome == Liquidated
│ └── Check: ethBalance = previous
└── outcome == Processed
└── Check: ethBalance = previous + securityDeposit

## POSCLOSI_04 (Sender wstETH Balance Check)

├── outcome == Liquidated
│ └── liquidator == sender
│ └── Check: wstETHBalance = previous + liquidationRewards
└── outcome == Processed
└── positionsLiquidatable || positionWasLiquidatedMeanwhile
└── liquidator == sender
└── Check: wstETHBalance = previous + liquidationRewards

## POSCLOSI_05 (Protocol wstETH Balance Check)

!rebalancerTriggered
├── feeCollectorCallbackTriggered
│ ├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ │ └── Check: Balance = previous - fees - liquidationRewards
│ └── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
│ └── Check: Balance = previous - fees
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── Check: Balance = previous - liquidationRewards
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: Balance = previous

# POSCLOSV Invariant Trees

## POSCLOSV_01 (Sender ETH Balance Check)

outcome == Processed && SINGLE_ACTOR_MODE == true
└── Check: ethBalance = previous + securityDeposit - pythPrice

## POSCLOSV_02 (Protocol ETH Balance Check)

outcome == Processed && SINGLE_ACTOR_MODE == true
└── Check: ethBalance = previous - securityDeposit

## POSCLOSV_03 (Protocol wstETH Balance First Check)

outcome == Processed
├── feeCollectorCallbackTriggered
│ └── Check: Balance = previous - closeAmount - positionProfit - fees
└── !feeCollectorCallbackTriggered
└── Check: Balance = previous - closeAmount - positionProfit

## POSCLOSV_04 (Protocol wstETH Balance Second Check)

├── outcome == Liquidated
│ └── liquidator == validator
│ ├── feeCollectorCallbackTriggered
│ │ └── Check: Balance >= previous - closeAmount - pendingActions - liquidationRewards - fees
│ └── !feeCollectorCallbackTriggered
│ └── Check: Balance >= previous - closeAmount - pendingActions - liquidationRewards
└── outcome == Processed
├── feeCollectorCallbackTriggered
│ ├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ │ └── Check: Balance >= previous - closeAmount - pendingActions - profit - fees - liquidationRewards
│ └── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
│ └── Check: Balance >= previous - closeAmount - pendingActions - profit - fees
└── !feeCollectorCallbackTriggered
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── Check: Balance >= previous - closeAmount - pendingActions - profit - liquidationRewards
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: Balance >= previous - closeAmount - pendingActions - profit

## POSCLOSV_05 (User wstETH Balance Upper Bounds Check)

├── outcome == Liquidated
│ └── liquidator == validator
│ └── Check: Balance <= previous + closeAmount + liquidationRewards + profit
└── outcome == Processed
└── Check: Balance <= previous + closeAmount + profit

## POSCLOSV_06 (User wstETH Balance Exact Check)

outcome == Processed
└── Check: Balance = previous + closeAmount + profit

## POSCLOSV_07 (Validator ETH Balance Invariance Check)

outcome == Processed && caller != validator
└── Check: ethBalance = previous

## POSCLOSV_08 (Caller wstETH Balance Invariance Check)

outcome == Processed && caller != user
└── Check: wstETHBalance = previous

## POSCLOSV_09 (User ETH Balance Invariance Check)

outcome == Processed && validator != user
└── Check: ethBalance = previous

## POSCLOSV_10 (Validator wstETH Balance Invariance Check)

outcome == Processed && validator != user
└── Check: wstETHBalance = previous

# DEPI Invariant Trees

## DEPI_01 (User ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedDeposit
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous - pythPrice
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous - securityDeposit - pythPrice
│ └── !initiatedDeposit
│ └── Check: ethBalance = previous - pythPrice
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous - securityDeposit - pythPrice

## DEPI_02 (User wstETH Balance Check)

!rebalancerTriggered
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── liquidator == validator
│ └── Check: wstETHBalance = previous - wstEthAmount + liquidationRewards + positionProfit
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: wstETHBalance = previous - wstEthAmount + positionProfit

## DEPI_03 (SDEX Balance Check)

└── Check: sdexBalance < previous sdexBalance

## DEPI_04 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedDeposit
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous + securityDeposit
│ └── !initiatedDeposit
│ └── Check: ethBalance = previous
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous + securityDeposit - lastAction.securityDepositValue

## DEPI_05 (Protocol wstETH Balance Check)

!rebalancerTriggered
├── feeCollectorCallbackTriggered
│ ├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ │ └── Check: Balance = previous + wstEthAmount - pendingActions - fees - liquidationRewards - profit
│ └── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
│ └── Check: Balance = previous + wstEthAmount - pendingActions - fees - profit
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── Check: Balance = previous + wstEthAmount - pendingActions - liquidationRewards - profit
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: Balance = previous + wstEthAmount - pendingActions - profit

# DEPV Invariant Trees

## DEPV_01 (User USDN Shares Check)

└── Check: usdnShares > previous usdnShares

## DEPV_02 (Caller USDN Shares Check)

└── user != caller
└── Check: usdnShares = previous usdnShares

## DEPV_03 (Validator USDN Shares Check)

└── user != validator
└── Check: usdnShares = previous usdnShares

## DEPV_04 (ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── user != validator
│ └── Check: ethBalance = previous + securityDeposit
└── user == validator
└── Check: ethBalance = previous + securityDeposit - pythPrice

## DEPV_05 (USDN Total Supply Check)

└── Check: usdnTotalSupply = previous + expectedUsdn (with tolerance of 1)

## DEPV_06 (Caller wstETH Balance Check)

positionsLiquidatable || positionWasLiquidatedMeanwhile
├── liquidator == caller
│ └── Check: wstETHBalance = previous + liquidationRewards
└── liquidator != caller
└── Check: wstETHBalance = previous

## DEPV_07 (Protocol wstETH Balance Check)

!rebalancerTriggered
├── feeCollectorCallbackTriggered
│ ├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ │ ├── liquidator == validator
│ │ │ └── Check: Balance = previous - pendingActions - fees - liquidationRewards
│ │ └── liquidator != validator
│ │ └── Check: Balance = previous - pendingActions - fees
│ └── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
│ └── Check: Balance = previous - pendingActions - fees
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── liquidator == validator
│ │ └── Check: Balance = previous - pendingActions - liquidationRewards
│ └── liquidator != validator
│ └── Check: Balance = previous - pendingActions
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: Balance = previous - pendingActions

## DEPV_08 (Validator wstETH Balance Check)

├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── liquidator != validator
│ └── Check: wstETHBalance = previous
└── feeCollectorCallbackTriggered
└── currentActor != validator
└── Check: wstETHBalance = previous

## DEPV_09 (User wstETH Balance Check)

├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ └── liquidator != user
│ └── Check: wstETHBalance = previous
└── feeCollectorCallbackTriggered
└── currentActor != user
└── Check: wstETHBalance = previous

# WITHI Invariant Trees

## WITHI_01 (User ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedWithdrawal
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous - pythPrice
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous - securityDeposit - pythPrice
│ └── !initiatedWithdrawal
│ └── Check: ethBalance = previous - pythPrice
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous - securityDeposit - pythPrice

## WITHI_02 (User USDN Shares Check)

└── Check: usdnShares = previous - params.usdnShares (with tolerance of 1)

## WITHI_03 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── initiatedWithdrawal
│ │ ├── positionWasLiquidatedMeanwhile
│ │ │ └── Check: ethBalance = previous
│ │ └── !positionWasLiquidatedMeanwhile
│ │ └── Check: ethBalance = previous + securityDeposit
│ └── !initiatedWithdrawal
│ └── Check: ethBalance = previous
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous + securityDeposit - lastAction.securityDepositValue

## WITHI_04 (Protocol USDN Shares Check)

!states[0].otherUsersPendingActions
└── Check: usdnShares = previous + params.usdnShares + usdnPendingActions

# WITHV Invariant Trees

## WITHV_01 (User ETH Balance Check)

SINGLE_ACTOR_MODE == true
└── Check: ethBalance = previous + securityDeposit - pythPrice

## WITHV_02 (User wstETH Balance Check)

└── Check: wstETHBalance >= previous wstETHBalance

## WITHV_03 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true
└── Check: ethBalance = previous - securityDeposit

## WITHV_04 (Protocol USDN Shares Check)

└── Check: usdnShares <= previous + usdnPendingActions

## WITHV_05 (Protocol wstETH Balance Check)

└── Check: wstETHBalance <= previous - withdrawAssetToTransferAfterFees

# PENDACTV Invariant Trees

## PENDACTV_01 (Validations Count Check)

├── actionsLength == 0
│ └── Check: validatedActions = 1
└── maxValidations > 0 && actionsLength > maxValidations
└── Check: validatedActions = maxValidations

## PENDACTV_02 (Validator ETH Balance Check)

SINGLE_ACTOR_MODE == true && actionsLength != 0
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── !liquidationPending
│ │ └── Check: ethBalance = previous + securityDeposit - pythPrice
│ └── liquidationPending
│ └── Check: ethBalance = previous - pythPrice
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous + securityDeposit - pythPrice

## PENDACTV_03 (Protocol ETH Balance Check)

SINGLE_ACTOR_MODE == true && actionsLength != 0
├── positionsLiquidatable || positionWasLiquidatedMeanwhile
│ ├── !liquidationPending
│ │ └── Check: ethBalance = previous - securityDeposit
│ └── liquidationPending
│ └── Check: ethBalance = previous
└── !(positionsLiquidatable || positionWasLiquidatedMeanwhile)
└── Check: ethBalance = previous - securityDeposit

## GLOB_01 (Highest Tick Check)

highestActualTick != 0
└── Check: getHighestPopulatedTick >= highestActualTick

## GLOB_02 (Divisor Check)

└── Check: divisor != MIN_DIVISOR

## GLOB_03 (Last Funding Check)

lastFundingSwitch
└── Check: lastFunding != 0

## GLOB_04 (Security Deposit Coverage Check)

pendingActionsLength > 0
└── Check: protocolEthBalance >= pendingActionsLength \* securityDeposit

## GLOB_05 (Trading Expo Check)

totalLongPositions > 0
└── Check: tradingExpo > 0

## GLOB_06 (Low Leverage Positions Count Check)

└── Check: lowLeveragePositionsCount = 0

## GLOB_07 (Protocol Balance Check)

protocolFeeBps == 0 && calculatedBalance >= 0 && currentBalance <= calculatedBalance
└── Check: calculatedBalance ≈ currentBalance (within 1% tolerance)
Where calculatedBalance = vaultBalance + balanceLong + pendingProtocolFee + pendingVaultBalance
```

## Fuzzing suite tree

```
├── test
   └── fuzzing
       ├── FoundryPlayground.sol
       ├── Fuzz.sol
       ├── FuzzAdmin.sol
       ├── FuzzGuided.sol
       ├── FuzzRebalancer.sol
       ├── FuzzSetup.sol
       ├── FuzzUsdnProtocolActions.sol
       ├── FuzzUsdnProtocolVault.sol
       │
       ├── helper
       │   ├── BeforeAfter.sol
       │   ├── FuzzStorageVariables.sol
       │   ├── FuzzStructs.sol
       │   │
       │   ├── postconditions
       │   │   ├── PostconditionsAdmin.sol
       │   │   ├── PostconditionsBase.sol
       │   │   ├── PostconditionsRebalancer.sol
       │   │   ├── PostconditionsUsdnProtocolActions.sol
       │   │   └── PostconditionsUsdnProtocolVault.sol
       │   │
       │   └── preconditions
       │       ├── PreconditionsAdmin.sol
       │       ├── PreconditionsBase.sol
       │       ├── PreconditionsRebalancer.sol
       │       ├── PreconditionsUsdnProtocolActions.sol
       │       └── PreconditionsUsdnProtocolVault.sol
       │
       ├── mocks
       │   ├── IUsdnProtocolHandler.sol
       │   ├── MockPyth.sol
       │   └── UsdnProtocolHandler.sol
       │
       ├── properties
       │   ├── Properties.sol
       │   ├── PropertiesBase.sol
       │   ├── PropertiesDescriptions.sol
       │   ├── Properties_DEPI.sol
       │   ├── Properties_DEPV.sol
       │   ├── Properties_ERR.sol
       │   ├── Properties_GLOB.sol
       │   ├── Properties_LIQ.sol
       │   ├── Properties_PENDACTV.sol
       │   ├── Properties_POSCLOSI.sol
       │   ├── Properties_POSCLOSV.sol
       │   ├── Properties_POSOPNI.sol
       │   ├── Properties_POSOPNV.sol
       │   ├── Properties_WITHI.sol
       │   └── Properties_WITHV.sol
       │
       ├── reproducers
       │   ├── CurrentReproducers.sol
       │   ├── Reproducers.sol
       │   ├── ReproducersBase.sol
       │   └── ValidReproducers.sol
       │
       ├── slither
       │
       └── util
           ├── FunctionCalls.sol
           ├── FuzzActors.sol
           └── FuzzConstants.sol
```

## Suite invariants table

| Invariant ID | Invariant Description                                                                            | Passed | Remediations | Run Count |
| ------------ | ------------------------------------------------------------------------------------------------ | ------ | ------------ | --------- |
| GLOB-01      | A positions tick should never be above the \_highestPopulatedTick                                | ✅     | ✅           | 10m       |
| GLOB-02      | The current divisor should never equal the MIN_DIVISOR.”                                         | ✅     | ✅           | 10m       |
| GLOB-03      | FundingPerDay should never equal 0                                                               | ✅     | ✅           | 10m       |
| GLOB-04      | Each pending action should have an associated securityDeposit value.                             | ✅     | ✅           | 10m       |
| GLOB-05      | Trading expo should never go to 0.                                                               | ✅     | ✅           | 10m       |
| GLOB-06      | Position should never have a leverage smaller that 1.                                            | ✅     | ✅           | 10m       |
| GLOB-07      | The internal total balance the contract deals with should not be bigger than the real balanceOf. | ✅     | ✅           | 10m       |
| ERR-01       | Non-whitelisted error should never appear in a call                                              | ❌     | ✅           | 10m       |
| DEPI-01      | Sender's ETH balance decreased by security deposit                                               | ✅     | ✅           | 10m       |
| DEPI-02      | Sender's wstETH balance decreased by deposited amount                                            | ✅     | ✅           | 10m       |
| DEPI-03      | Sender's SDEX balance decreased                                                                  | ✅     | ✅           | 10m       |
| DEPI-04      | Protocol's ETH balance increased by security deposit                                             | ✅     | ✅           | 10m       |
| DEPI-05      | Protocol's wstETH balance increased by deposit minus pending actions                             | ✅     | ✅           | 10m       |
| DEPV-01      | Recipient's USDN shares increased after validation                                               | ✅     | ✅           | 10m       |
| DEPV-02      | Caller’s USDN shares unchanged                                                                   | ✅     | ✅           | 10m       |
| DEPV-03      | Validator’s USDN shares unchanged                                                                | ✅     | ✅           | 10m       |
| DEPV-04      | Validator's ETH balance increased by security deposit after validation                           | ✅     | ✅           | 10m       |
| DEPV-05      | USDN token total supply changed by pending tokens after validation                               | ✅     | ✅           | 10m       |
| DEPV-06      | Caller’s wstETH balance unchanged                                                                | ✅     | ✅           | 10m       |
| DEPV-07      | Protocol's wstETH balance decreased by pending actions after validation                          | ✅     | ✅           | 10m       |
| DEPV-08      | Validator's wstETH balance unchanged                                                             | ✅     | ✅           | 10m       |
| DEPV-09      | Caller’s wstETH balance unchanged                                                                | ✅     | ✅           | 10m       |
| WITHI-01     | Sender's ETH balance decreased by security deposit                                               | ✅     | ✅           | 10m       |
| WITHI-02     | Sender's USDN shares decreased by withdrawn amount                                               | ✅     | ✅           | 10m       |
| WITHI-03     | Protocol's ETH balance increased by security deposit minus last action's deposit                 | ✅     | ✅           | 10m       |
| WITHI-04     | Protocol's USDN shares increased by withdrawn amount plus pending actions                        | ✅     | ✅           | 10m       |
| WITHV-01     | Sender's ETH balance increased by action's security deposit value                                | ✅     | ✅           | 10m       |
| WITHV-02     | If successful, sender's wstETH balance increased or remained the same                            | ✅     | ✅           | 10m       |
| WITHV-03     | If successful, protocol's ETH balance decreased by action's security deposit value               | ✅     | ✅           | 10m       |
| WITHV-04     | If successful, protocol's USDN shares decreased                                                  | ✅     | ✅           | 10m       |
| WITHV-05     | If successful, protocol's wstETH balance decreased by at least pending actions                   | ✅     | ✅           | 10m       |
| POSOPNI-01   | Protocol's ETH balance increased by security deposit minus last action                           | ✅     | ✅           | 10m       |
| POSOPNI-02   | Sender's ETH balance decreased by security deposit minus last action                             | ✅     | ✅           | 10m       |
| POSOPNI-03   | Protocol's wstETH balance increased by deposit amount minus pending actions                      | ✅     | ✅           | 10m       |
| POSOPNI-04   | Sender's wstETH balance decreased by deposit amount                                              | ✅     | ✅           | 10m       |
| POSCLOSI-01  | If successful, sender's ETH balance decreased by security deposit                                | ✅     | ✅           | 10m       |
| POSCLOSI-02  | If successful, validator's pending action is set to ValidateClosePosition                        | ✅     | ✅           | 10m       |
| POSCLOSI-03  | If successful, protocol's ETH balance increased by security deposit                              | ✅     | ✅           | 10m       |
| POSCLOSI-04  | Sender's wstETH balance unchanged                                                                | ✅     | ✅           | 10m       |
| POSCLOSI-05  | Protocol's wstETH balance unchanged                                                              | ✅     | ✅           | 10m       |
| POSOPNV-01   | If successful, validator's ETH balance increased by security deposits                            | ✅     | ✅           | 10m       |
| POSOPNV-02   | If successful, protocol's ETH balance decreased by security deposits                             | ✅     | ✅           | 10m       |
| POSOPNV-05   | Protocol's wstETH balance decreased by pending actions                                           | ✅     | ✅           | 10m       |
| POSOPNV-06   | Sender's wstETH balance unchanged                                                                | ✅     | ✅           | 10m       |
| POSCLOSV-01  | If successful, sender's ETH balance increased by security deposit                                | ✅     | ✅           | 10m       |
| POSCLOSV-02  | If successful, protocol's ETH balance decreased by security deposit                              | ✅     | ✅           | 10m       |
| POSCLOSV-03  | If successful, protocol's wstETH balance decreased by more than pending actions                  | ✅     | ✅           | 10m       |
| POSCLOSV-04  | If successful, protocol's wstETH balance decreased by less than close amount + pending actions   | ✅     | ✅           | 10m       |
| POSCLOSV-05  | If successful, recipient's wstETH balance increased by less than close amount                    | ✅     | ✅           | 10m       |
| POSCLOSV-06  | If successful, recipient's wstETH balance increased                                              | ❌     | ✅           | 10m       |
| POSCLOSV-07  | If successful and sender != validator, validator's ETH balance unchanged                         | ✅     | ✅           | 10m       |
| POSCLOSV-08  | If successful and sender != recipient, sender's wstETH balance unchanged                         | ✅     | ✅           | 10m       |
| POSCLOSV-09  | If successful and recipient != validator, recipient's ETH balance unchanged                      | ✅     | ✅           | 10m       |
| POSCLOSV-10  | If successful and recipient != validator, validator's wstETH balance unchanged                   | ✅     | ✅           | 10m       |
| PENDACTV-01  | Correct number of actions validated                                                              | ✅     | ✅           | 10m       |
| PENDACTV-02  | Sender's ETH balance increased by security deposit                                               | ✅     | ✅           | 10m       |
| PENDACTV-03  | Protocol's ETH balance decreased by security deposit                                             | ✅     | ✅           | 10m       |
