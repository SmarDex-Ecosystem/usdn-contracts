// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UsdnProtocolImmutables } from "src/UniversalRouter/modules/usdn/UsdnProtocolImmutables.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract UsdnProtocolRouter is UsdnProtocolImmutables {
    using SafeCast for uint256;
    using SafeERC20 for IERC20Metadata;

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
     * @param depositPriceData The price data at the time of the deposit
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
}
