# Fuzzer-Added Variables Implementation Summary

The following table summarizes the variables added by the fuzzer across different files and functions to track state for testing purposes.

## **UsdnProtocolLongLibrary.sol**

| Variable               | Function                | Purpose                                              |
|------------------------|------------------------|------------------------------------------------------|
| `_liquidationPending`   | `_liquidatePositions`   | Tracks if there are positions pending liquidation   |
| `_positionLiquidated`   | `_liquidatePositions`   | Flags when positions have been liquidated          |
| `_lowestLiquidatedTick` | `_liquidatePositions`   | Records the lowest tick that was liquidated        |
| `_positionProfit`       | `_flashClosePosition`   | Tracks the profit/loss when a position is closed   |
| `_fuzz_liquidator`      | `_sendRewardsToLiquidator` | Records the address of the liquidator            |
| `_fuzz_liquidationRewards` | `_sendRewardsToLiquidator` | Records the amount of rewards sent to liquidator |
| `_rebalancerTriggered`  | `_triggerRebalancer`    | Flags when the rebalancer has been triggered       |

---

## **UsdnProtocolActionsLongLibrary.sol**

| Variable                            | Function                             | Purpose                                              |
|-------------------------------------|-------------------------------------|------------------------------------------------------|
| `_positionWasLiquidatedInTheMeantime` | `_prepareValidateOpenPositionData`   | Flags when a position was liquidated while pending validation |
| `_positionProfit`                    | `_validateClosePositionWithAction`   | Records the profit/loss when a position is closed with validation |
| `_latestPosIdTick`                   | `_initiateOpenPosition`              | Records the tick of the most recently created position |

---

## **UsdnProtocolCoreLibrary.sol**

| Variable                            | Function                | Purpose                                              |
|-------------------------------------|------------------------|------------------------------------------------------|
| `_positionWasLiquidatedInTheMeantime` | `_removeStalePendingAction` | Flags when a position was liquidated before pending action could be processed |

---

## **UsdnProtocolVaultLibrary.sol**

| Variable                               | Function                          | Purpose                                                 |
|----------------------------------------|----------------------------------|---------------------------------------------------------|
| `_withdrawAssetToTransferAfterFees`      | `_validateWithdrawalWithAction`  | Records the amount of assets to transfer after fees during withdrawal |

---

## **Summary**

| File                                | Number of Functions to Modify |
|-------------------------------------|------------------------------|
| **UsdnProtocolLongLibrary.sol**     | 5 |
| **UsdnProtocolActionsLongLibrary.sol** | 3 |
| **UsdnProtocolCoreLibrary.sol**     | 1 |
| **UsdnProtocolVaultLibrary.sol**    | 1 |

---
