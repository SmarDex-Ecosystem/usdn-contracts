// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocol } from "../UsdnProtocol/IUsdnProtocol.sol";
import { IBaseRebalancer } from "./IBaseRebalancer.sol";
import { IRebalancerErrors } from "./IRebalancerErrors.sol";
import { IRebalancerEvents } from "./IRebalancerEvents.sol";
import { IRebalancerTypes } from "./IRebalancerTypes.sol";

interface IRebalancer is IBaseRebalancer, IRebalancerErrors, IRebalancerEvents, IRebalancerTypes {
    /**
     * @notice Gets the value of the multiplier at 1x.
     * @dev Also helps to normalize the result of multiplier calculations.
     * @return factor_ The multiplier factor.
     */
    function MULTIPLIER_FACTOR() external view returns (uint256 factor_);

    /**
     * @notice The maximum cooldown time between actions.
     * @return cooldown_ The maximum cooldown time between actions.
     */
    function MAX_ACTION_COOLDOWN() external view returns (uint256 cooldown_);

    /**
     * @notice The EIP712 {initiateClosePosition} typehash.
     * @dev By including this hash into the EIP712 message for this domain, this can be used together with
     * [ECDSA-recover](https://docs.openzeppelin.com/contracts/5.x/api/utils#ECDSA) to obtain the signer of a message.
     * @return typehash_ The EIP712 {initiateClosePosition} typehash.
     */
    function INITIATE_CLOSE_TYPEHASH() external view returns (bytes32 typehash_);

    /**
     * @notice Gets the maximum amount of seconds to wait to execute a {initiateClosePosition} since a new rebalancer
     * long position has been created.
     * @return closeDelay_ The max close delay value.
     */
    function MAX_CLOSE_DELAY() external view returns (uint256 closeDelay_);

    /**
     * @notice Returns the address of the asset used by the USDN protocol.
     * @return asset_ The address of the asset used by the USDN protocol.
     */
    function getAsset() external view returns (IERC20Metadata asset_);

    /**
     * @notice Returns the address of the USDN protocol.
     * @return protocol_ The address of the USDN protocol.
     */
    function getUsdnProtocol() external view returns (IUsdnProtocol protocol_);

    /**
     * @notice Returns the version of the current position (0 means no position open).
     * @return version_ The version of the current position.
     */
    function getPositionVersion() external view returns (uint128 version_);

    /**
     * @notice Returns the maximum leverage the rebalancer position can have.
     * @dev In some edge cases during the calculation of the rebalancer position's tick, this value might be
     * exceeded by a slight margin.
     * @dev Returns the max leverage of the USDN Protocol if it's lower than the rebalancer's.
     * @return maxLeverage_ The maximum leverage.
     */
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_);

    /**
     * @notice Returns the amount of assets deposited and waiting for the next version to be opened.
     * @return _pendingAssetsAmount The amount of pending assets.
     */
    function getPendingAssetsAmount() external view returns (uint128 _pendingAssetsAmount);

    /**
     * @notice Returns the data of the provided version of the position.
     * @param version The version of the position.
     * @return positionData_ The data for the provided version of the position.
     */
    function getPositionData(uint128 version) external view returns (PositionData memory positionData_);

    /**
     * @notice Gets the time limits for the action validation process.
     * @return timeLimits_ The time limits.
     */
    function getTimeLimits() external view returns (TimeLimits memory timeLimits_);

    /**
     * @notice Increases the allowance of assets for the USDN protocol spender by `addAllowance`.
     * @param addAllowance Amount to add to the allowance of the USDN Protocol.
     */
    function increaseAssetAllowance(uint256 addAllowance) external;

    /**
     * @notice Returns the version of the last position that got liquidated.
     * @dev 0 means no liquidated version yet.
     * @return version_ The version of the last position that got liquidated.
     */
    function getLastLiquidatedVersion() external view returns (uint128 version_);

    /**
     * @notice Gets the nonce a user can use to generate a delegation signature.
     * @dev This is to prevent replay attacks when using an EIP712 delegation signature.
     * @param user The user address of the deposited amount in the rebalancer.
     * @return nonce_ The user's nonce.
     */
    function getNonce(address user) external view returns (uint256 nonce_);

    /**
     * @notice Gets the domain separator v4 used for EIP-712 signatures.
     * @return domainSeparator_ The domain separator v4.
     */
    function domainSeparatorV4() external view returns (bytes32 domainSeparator_);

    /**
     * @notice Gets the timestamp by which a user must wait to perform a {initiateClosePosition}.
     * @return timestamp_ The timestamp until which the position cannot be closed.
     */
    function getCloseLockedUntil() external view returns (uint256 timestamp_);

    /**
     * @notice Deposits assets into this contract to be included in the next position after validation
     * @dev The user must call {validateDepositAssets} between `_timeLimits.validationDelay` and.
     * `_timeLimits.validationDeadline` seconds after this action.
     * @param amount The amount in assets that will be deposited into the rebalancer.
     * @param to The address which will need to validate and which will own the position.
     */
    function initiateDepositAssets(uint88 amount, address to) external;

    /**
     * @notice Validates a deposit to be included in the next position version.
     * @dev The `to` from the `initiateDepositAssets` must call this function between `_timeLimits.validationDelay` and
     * `_timeLimits.validationDeadline` seconds after the initiate action. After that, the user must wait until
     * `_timeLimits.actionCooldown` seconds has elapsed, and then can call `resetDepositAssets` to retrieve their
     * assets.
     */
    function validateDepositAssets() external;

    /**
     * @notice Retrieves the assets for a failed deposit due to waiting too long before calling {validateDepositAssets}.
     * @dev The user must wait `_timeLimits.actionCooldown` since the {initiateDepositAssets} before calling this
     * function.
     */
    function resetDepositAssets() external;

    /**
     * @notice Withdraws assets that were not yet included in a position.
     * @dev The user must call {validateWithdrawAssets} between `_timeLimits.validationDelay` and
     * `_timeLimits.validationDeadline` seconds after this action.
     */
    function initiateWithdrawAssets() external;

    /**
     * @notice Validates a withdrawal of assets that were not yet included in a position.
     * @dev The user must call this function between `_timeLimits.validationDelay` and `_timeLimits.validationDeadline`
     * seconds after {initiateWithdrawAssets}. After that, the user must wait until the cooldown has elapsed, and then
     * can call {initiateWithdrawAssets} again or wait to be included in the next position.
     * @param amount The amount of assets to withdraw.
     * @param to The recipient of the assets.
     */
    function validateWithdrawAssets(uint88 amount, address to) external;

    /**
     * @notice Closes the provided amount from the current rebalancer's position.
     * @dev The rebalancer allows partially closing its position to withdraw the user's assets + PnL.
     * The remaining amount needs to be above `_minAssetDeposit`. The validator is always the `msg.sender`, which means
     * the user must call `validateClosePosition` on the protocol side after calling this function.
     * @param amount The amount to close relative to the amount deposited.
     * @param to The recipient of the assets.
     * @param validator The address that should validate the open position.
     * @param userMinPrice The minimum price at which the position can be closed.
     * @param deadline The deadline of the close position to be initiated.
     * @param currentPriceData The current price data.
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param delegationData An optional delegation data that include the depositOwner and an EIP712 signature to
     * provide when closing a position on the owner's behalf.
     * If used, it needs to be encoded with `abi.encode(depositOwner, abi.encodePacked(r, s, v))`.
     * @return outcome_ The outcome of the UsdnProtocol's `initiateClosePosition` call, check
     * {IUsdnProtocolActions.initiateClosePosition} for more details.
     */
    function initiateClosePosition(
        uint88 amount,
        address to,
        address payable validator,
        uint256 userMinPrice,
        uint256 deadline,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationData
    ) external payable returns (Types.LongActionOutcome outcome_);

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Updates the max leverage a position can have.
     * @dev `newMaxLeverage` must be between the min and max leverage of the USDN protocol.
     * This function can only be called by the owner of the contract.
     * @param newMaxLeverage The new max leverage.
     */
    function setPositionMaxLeverage(uint256 newMaxLeverage) external;

    /**
     * @notice Sets the various time limits in seconds.
     * @dev This function can only be called by the owner of the contract.
     * @param validationDelay The amount of time to wait before an initiate can be validated.
     * @param validationDeadline The amount of time a user has to validate an initiate.
     * @param actionCooldown The amount of time to wait before .
     * @param closeDelay The close delay that will be applied to the next long position opening.
     */
    function setTimeLimits(uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
        external;
}
