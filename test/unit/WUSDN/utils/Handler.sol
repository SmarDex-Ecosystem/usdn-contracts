// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { Usdn } from "src/Usdn.sol";
import { Wusdn } from "src/Wusdn.sol";

/**
 * @title WusdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract WusdnHandler is Wusdn, Test {
    Usdn public _usdn;

    // use multiple actors for invariant testing
    address[] public actors;

    // current actor
    address internal _currentActor;

    constructor(address[] memory _actors, Usdn usdn) Wusdn(usdn) {
        actors = _actors;
        _usdn = usdn;
    }

    /* ------------------ Functions used for invariant testing ------------------ */

    modifier useActor(uint256 actorIndexSeed) {
        console2.log("bound actor ID");
        _currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    function depositTest(uint256 assets, uint256 receiverIndexSeed, uint256 actorIndexSeed)
        external
        useActor(actorIndexSeed)
    {
        console2.log("bound deposit");
        if (_usdn.balanceOf(_currentActor) == 0) {
            return;
        }
        assets = bound(assets, 0, _usdn.balanceOf(_currentActor));
        uint256 newShares = previewDeposit(assets);

        _usdn.approve(address(this), assets);

        vm.stopPrank();
        vm.startPrank(address(this));
        _deposit(_currentActor, actors[bound(receiverIndexSeed, 0, actors.length - 1)], assets, newShares);
    }

    function withdrawTest(uint256 assets, uint256 receiverIndexSeed, uint256 actorIndexSeed)
        external
        useActor(actorIndexSeed)
    {
        console2.log("bound withdraw");
        if (balanceOf(_currentActor) == 0) {
            return;
        }
        uint256 maxAssets = convertToAssets(balanceOf(_currentActor));
        assets = bound(assets, 0, maxAssets);
        uint256 burnShares = previewWithdraw(assets);

        vm.stopPrank();
        vm.startPrank(address(this));
        _withdraw(
            _currentActor, actors[bound(receiverIndexSeed, 0, actors.length - 1)], _currentActor, assets, burnShares
        );
    }
}
