// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolImmutables } from "src/UniversalRouter/modules/usdn/UsdnProtocolImmutables.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract UsdnProtocolRouter is UsdnProtocolImmutables {
    using SafeCast for uint256;

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
    function usdnInitiateDeposit(
        uint128 amount,
        address to,
        address validator,
        bytes memory currentPriceData,
        PreviousActionsData memory previousActionsData
    ) internal returns (bool success_) {
        // use amount == Constants.CONTRACT_BALANCE as a flag to deposit the entire balance of the contract
        if (amount == Constants.CONTRACT_BALANCE) {
            amount = PROTOCOL_ASSET.balanceOf(address(this)).toUint128();
        }
        USDN_PROTOCOL.initiateDeposit(amount, to, validator, currentPriceData, previousActionsData);
        success_ = true; // TODO: retrieve success status from initiateDeposit return value (when implemented)
    }
}
