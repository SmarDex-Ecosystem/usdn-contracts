// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Permit2Payments } from "@uniswap/universal-router/contracts/modules/Permit2Payments.sol";

import { UsdnProtocolImmutables } from "src/UniversalRouter/modules/usdn/UsdnProtocolImmutables.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IWusdn } from "src/interfaces/Usdn/IWusdn.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

abstract contract UsdnProtocolRouter is UsdnProtocolImmutables, Permit2Payments {
    using SafeCast for uint256;
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;

    /**
     * @notice Initiate a deposit into the USDN protocol vault
     * @dev Check the protocol's documentation for information about how this function should be used
     * Note: the deposit can fail without reverting, in case there are some pending liquidations in the protocol
     * @param amount The amount of asset to deposit into the vault
     * @param to The address that will receive the USDN tokens upon validation
     * @param validator The address that should validate the deposit (receives the security deposit back)
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the deposit was successful
     */
    function _usdnInitiateDeposit(
        uint256 amount,
        address to,
        address validator,
        bytes memory currentPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_) {
        // use amount == Constants.CONTRACT_BALANCE as a flag to deposit the entire balance of the contract
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = PROTOCOL_ASSET.balanceOf(address(this));
        }
        PROTOCOL_ASSET.forceApprove(address(USDN_PROTOCOL), amount);
        SDEX.approve(address(USDN_PROTOCOL), type(uint256).max);
        // we send the full ETH balance, the protocol will refund any excess
        success_ = USDN_PROTOCOL.initiateDeposit{ value: address(this).balance }(
            amount.toUint128(), to, validator, currentPriceData, previousActionsData
        );
        SDEX.approve(address(USDN_PROTOCOL), 0);
    }

    /**
     * @notice Validate a deposit into the USDN protocol vault
     * @dev Check the protocol's documentation for information about how this function should be used
     * @param validator The address that should validate the deposit (receives the security deposit)
     * @param depositPriceData The price data corresponding to the validator's pending deposit action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the deposit was successfully
     */
    function _usdnValidateDeposit(
        address validator,
        bytes memory depositPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_) {
        success_ = USDN_PROTOCOL.validateDeposit{ value: address(this).balance }(
            validator, depositPriceData, previousActionsData
        );
    }

    /**
     * @notice Initiate a withdrawal from the USDN protocol vault
     * @dev Check the protocol's documentation for information about how this function should be used
     * Note: the withdrawal can fail without reverting, in case there are some pending liquidations in the protocol
     * @param amount The amount of USDN shares to burn
     * @param to The address that will receive the asset upon validation
     * @param validator The address that should validate the withdrawal (receives the security deposit back)
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the withdrawal was successful
     */
    function _usdnInitiateWithdrawal(
        uint256 amount,
        address to,
        address validator,
        bytes memory currentPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_) {
        // use amount == Constants.CONTRACT_BALANCE as a flag to withdraw the entire balance of the contract
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = USDN.sharesOf(address(this));
        }
        USDN.approve(address(USDN_PROTOCOL), USDN.convertToTokensRoundUp(amount));
        // we send the full ETH balance, the protocol will refund any excess
        success_ = USDN_PROTOCOL.initiateWithdrawal{ value: address(this).balance }(
            amount.toUint152(), to, validator, currentPriceData, previousActionsData
        );
    }

    /**
     * @notice Validate a withdrawal into the USDN protocol vault
     * @dev Check the protocol's documentation for information about how this function should be used
     * Note: the withdrawal can fail without reverting, in case there are some pending liquidations in the protocol
     * @param validator The address that should validate the withdrawal (receives the security deposit)
     * @param withdrawalPriceData The price data corresponding to the validator's pending deposit action
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the withdrawal was successful
     */
    function _usdnValidateWithdrawal(
        address validator,
        bytes memory withdrawalPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_) {
        success_ = USDN_PROTOCOL.validateWithdrawal{ value: address(this).balance }(
            validator, withdrawalPriceData, previousActionsData
        );
    }

    /**
     * @notice Initiate an open position in the USDN protocol
     * @dev Check the protocol's documentation for information about how this function should be used
     * Note: the open position can fail without reverting, in case there are some pending liquidations in the protocol
     * @param amount The amount of assets used to open the position
     * @param desiredLiqPrice The desired liquidation price for the position
     * @param to The address that will receive the position
     * @param validator The address that should validate the open position (receives the security deposit back)
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions
     * @return success_ Whether the open position was successful
     * @return posId_ The position ID of the newly opened position
     */
    function _usdnInitiateOpenPosition(
        uint256 amount,
        uint128 desiredLiqPrice,
        address to,
        address validator,
        bytes memory currentPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_, PositionId memory posId_) {
        // use amount == Constants.CONTRACT_BALANCE as a flag to deposit the entire balance of the contract
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = PROTOCOL_ASSET.balanceOf(address(this));
        }
        PROTOCOL_ASSET.forceApprove(address(USDN_PROTOCOL), amount);
        // we send the full ETH balance, and the protocol will refund any excess
        (success_, posId_) = USDN_PROTOCOL.initiateOpenPosition{ value: address(this).balance }(
            amount.toUint128(), desiredLiqPrice, to, validator, currentPriceData, previousActionsData
        );
    }

    /**
     * @notice Wrap the usdn value into wusdn
     * @param value The usdn value
     * @param receiver The wusdn receiver
     */
    function _wrapUSDN(uint256 value, address receiver) internal {
        uint256 balance = USDN.balanceOf(address(this));

        if (value == Constants.CONTRACT_BALANCE) {
            value = balance;
        } else if (value > balance) {
            revert InsufficientToken();
        }

        if (value > 0) {
            USDN.forceApprove(address(WUSDN), value);
            IWusdn(WUSDN).deposit(value, receiver);
        }
    }

    /**
     * @notice Unwrap the wusdn value into usdn
     * @param value The wusdn value
     * @param receiver The usdn receiver
     */
    function _unwrapUSDN(uint256 value, address receiver, address owner) internal {
        uint256 balance = WUSDN.balanceOf(address(this));

        if (value == Constants.CONTRACT_BALANCE) {
            value = balance;
        } else if (value > balance) {
            revert InsufficientToken();
        }

        if (value > 0) {
            WUSDN.redeem(value, receiver, owner);
        }
    }
}
