// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console, Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UsdnVault } from "src/UsdnVault/UsdnVault.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title UsdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract UsdnVaultHandler is UsdnVault, Test {
    // Position struct with tick and index added
    struct HandlerPosition {
        // Real data stored in the vault
        uint40 leverage;
        uint40 timestamp;
        bool isExit;
        bool validated;
        address user;
        uint128 amount;
        uint128 startPrice;
        // Additional data for invariant testing
        uint24 tick;
        uint256 index;
        bool waitingForEntry;
        bool waitingForExit;
    }

    // use multiple actors for invariant testing
    address[] public actors;

    // current actor
    address internal currentActor;

    // Actor positions
    mapping(address => HandlerPosition) public positionsTest;

    // Last pending pos
    int24 public lastActionTick;
    uint256 public lastActionIndex;

    constructor(
        IUsdn _usdn,
        IERC20Metadata _asset,
        IOracleMiddleware _oracleMiddleware,
        int24 _tickSpacing,
        address[] memory _actors
    ) UsdnVault(_usdn, _asset, _oracleMiddleware, _tickSpacing) {
        actors = _actors;
    }

    function yyy() public pure returns (bool) {
        return true;
    }

    function openLongTest(
        uint96 _deposit,
        uint128 _liquidationPrice,
        bytes calldata _assetPrice1,
        bytes calldata _assetPrice2,
        uint256 actorIndexSeed,
        uint8 time
    ) public payable useActor(actorIndexSeed) advanceTime(time) returns (int24 tick_, uint256 index_) {
        // Validate last pending position if exists
        if (lastActionTick != 0 && lastActionIndex != 0) {
            _validateLong(lastActionTick, lastActionIndex, _assetPrice2);
        }

        // Open a long position
        (tick_, index_) = _openLong(_deposit, _liquidationPrice, _assetPrice1);

        // Save last pending position for future validation
        lastActionTick = tick_;
        lastActionIndex = index_;
    }

    function closeLongTest(
        int24 _tick,
        uint256 _index,
        bytes calldata _assetPrice1,
        bytes calldata _assetPrice2,
        uint256 actorIndexSeed,
        uint8 time
    ) public payable useActor(actorIndexSeed) advanceTime(time) returns (int24 tick_, uint256 index_) {
        // Validate last pending position if exists
        if (lastActionTick != 0 && lastActionIndex != 0) {
            _validateLong(lastActionTick, lastActionIndex, _assetPrice2);
        }

        // Close a long position
        _closeLong(_tick, _index, _assetPrice1);

        // Save last pending position for future validation
        lastActionTick = tick_;
        lastActionIndex = index_;
    }

    function validateLongTest(
        int24 _tick,
        uint256 _index,
        bytes calldata _assetPrice1,
        bytes calldata _assetPrice2,
        uint256 actorIndexSeed,
        uint8 time
    ) public payable useActor(actorIndexSeed) advanceTime(time) {
        // Validate last pending position if exists
        if (lastActionTick != 0 && lastActionIndex != 0) {
            _validateLong(lastActionTick, lastActionIndex, _assetPrice2);
        }

        // Validate a long position
        _validateLong(_tick, _index, _assetPrice1);

        // Clear last pending position
        lastActionTick = 0;
        lastActionIndex = 0;
    }

    /* -------------------------------------------------------------------------- */
    /*                    Functions used for invariant testing                    */
    /* -------------------------------------------------------------------------- */

    modifier useActor(uint256 actorIndexSeed) {
        console.log("bound actor ID");
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier advanceTime(uint8 time) {
        _;
        skip(time);
    }
}
