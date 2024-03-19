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

    // track theoretical shares
    mapping(address account => uint256) public shares;

    // track theoretical total supply
    uint256 public totalSharesSum;

    constructor(address[] memory _actors, Usdn usdn) Wusdn(usdn) {
        actors = _actors;
        _usdn = usdn;
    }

    function approve(address _owner, address _spender, uint256 _value) external {
        _approve(_owner, _spender, _value);
    }

    function transfer(address _from, address _to, uint256 _value) external {
        _transfer(_from, _to, _value);
    }

    function burn(address _owner, uint256 _value) external {
        _burn(_owner, _value);
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
        if (_usdn.balanceOf(_currentActor) == 0) {
            return;
        }
        assets = bound(assets, 0, _usdn.balanceOf(_currentActor));
        uint256 newShares = previewDeposit(assets);

        _usdn.approve(_currentActor, assets);

        totalSharesSum += newShares;
        shares[_currentActor] += newShares;
        _deposit(_currentActor, actors[bound(receiverIndexSeed, 0, actors.length - 1)], assets, newShares);
        vm.stopPrank();
    }
}
