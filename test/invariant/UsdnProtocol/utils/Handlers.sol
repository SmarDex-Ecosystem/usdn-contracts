// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../../../utils/Constants.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";

import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @notice A handler for invariant testing of the USDN protocol
 * @dev This handler does not perform input validation and might result in reverted transactions
 * To perform invariant testing without unexpected reverts, use UsdnProtocolSafeHandler
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, UsdnProtocolFallback, Test {
    WstETH immutable _mockAsset;
    Sdex immutable _mockSdex;

    constructor(WstETH mockAsset, Sdex mockSdex) {
        _mockAsset = mockAsset;
        _mockSdex = mockSdex;
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function mine(uint256 rand) external {
        uint256 blocks = rand % 10;
        skip(12 * blocks);
        vm.roll(block.number + blocks);
    }

    function senders() public pure returns (address[] memory senders_) {
        senders_ = new address[](5);
        senders_[0] = ADMIN;
        senders_[1] = USER_1;
        senders_[2] = USER_2;
        senders_[3] = USER_3;
        senders_[4] = USER_4;
    }

    /* ----------------------- Exposed internal functions ----------------------- */

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        return Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator, tickSpacing, liquidationPenalty
        );
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return Utils._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    /* -------------------------------- Internal -------------------------------- */

    function _getPreviousActionsData() internal view returns (PreviousActionsData memory) {
        (PendingAction[] memory actions, uint128[] memory rawIndices) = Vault.getActionablePendingActions(s, msg.sender);
        return PreviousActionsData({ priceData: new bytes[](actions.length), rawIndices: rawIndices });
    }
}

/**
 * @notice A handler for invariant testing of the USDN protocol which does not revert in normal operation
 * @dev Inputs are sanitized to prevent reverts. If a call is not possible, each function is a no-op
 */
contract UsdnProtocolSafeHandler is UsdnProtocolHandler {
    constructor(WstETH mockAsset, Sdex mockSdex) UsdnProtocolHandler(mockAsset, mockSdex) { }

    /* ------------------------ Protocol actions helpers ------------------------ */

    function initiateDepositTest(uint128 amount, address to, address validator) external {
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        uint256 balance = s._asset.balanceOf(msg.sender);
        if (balance < s._minLongPosition) {
            return;
        }
        if (balance > type(uint128).max) {
            balance = type(uint128).max;
        }
        amount = uint128(bound(amount, s._minLongPosition, balance));
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.None, "");
        (, uint256 sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(block.timestamp));
        sdexToBurn = sdexToBurn * 15 / 10;
        _mockSdex.mintAndApprove(msg.sender, sdexToBurn, address(this), sdexToBurn);
        Vault.initiateDeposit(s, amount, 0, boundAddress(to), boundAddress(validator), "", _getPreviousActionsData());
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function boundAddress(address addr) public pure returns (address payable) {
        // there is a 50% chance of returning one of the senders, otherwise the input address
        if (uint256(uint160(addr)) % 2 == 0) {
            address[] memory senders = senders();
            return payable(senders[uint256(uint160(addr) / 2) % senders.length]);
        } else {
            return payable(addr);
        }
    }
}
