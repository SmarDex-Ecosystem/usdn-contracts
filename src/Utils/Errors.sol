// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                               Generic errors                               */
/* -------------------------------------------------------------------------- */

error AccessDenied();
error InvalidMaxIter();
error TimestampTooOld();
error ZeroAmount();

/* -------------------------------------------------------------------------- */
/*                              USDN Vault errors                             */
/* -------------------------------------------------------------------------- */

error FundingRateInvalid();
error IncompleteTransfer(uint256 amount, uint256 expected);
error InvalidFees();
error InvalidPriceData();
error InvalidPendingPosition();
error InvalidTicks();
error LeverageTooHigh();
error LeverageTooLow();
error MaxLeverageInvalid();
error MinLeverageInvalid();
error MinTotalSupply();
error NoPendingPosition();
error UserPositionAlreadyPending();
