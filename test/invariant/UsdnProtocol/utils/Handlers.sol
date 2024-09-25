// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../../../utils/Constants.sol";

import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @notice A handler for invariant testing of the USDN protocol
 * @dev This handler does not perform input validation and might result in reverted transactions
 * To perform invariant testing without unexpected reverts, use UsdnProtocolSafeHandler
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, UsdnProtocolFallback, Test {
    function senders() public pure returns (address[] memory senders_) {
        senders_ = new address[](5);
        senders_[0] = ADMIN;
        senders_[1] = USER_1;
        senders_[2] = USER_2;
        senders_[3] = USER_3;
        senders_[4] = USER_4;
    }

    function mine(uint256 rand) external {
        uint256 blocks = rand % 10;
        skip(12 * blocks);
        vm.roll(block.number + blocks);
    }

    /* --------------------------------- Helpers -------------------------------- */

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
}

/**
 * @notice A handler for invariant testing of the USDN protocol which does not revert in normal operation
 * @dev Inputs are sanitized to prevent reverts. If a call is not possible, each function is a no-op
 */
contract UsdnProtocolSafeHandler is UsdnProtocolHandler {
    function boundAddress(address addr) public pure returns (address) {
        // there is a 50% chance of returning one of the senders, otherwise the input address
        if (uint256(uint160(addr)) % 2 == 0) {
            address[] memory senders = senders();
            return senders[uint256(uint160(addr) / 2) % senders.length];
        } else {
            return addr;
        }
    }
}
