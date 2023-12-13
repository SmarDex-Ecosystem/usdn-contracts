// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console, Test } from "forge-std/Test.sol";

import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract UsdnHandler is Usdn, Test {
    // use multiple actors for invariant testing
    address[] public actors;

    // current actor
    address internal _currentActor;

    // track theoretical shares
    mapping(address account => uint256) public shares;

    // track theorectical total supply
    uint256 public totalSharesSum;

    constructor(address[] memory _actors) Usdn(address(0), address(0)) {
        actors = _actors;
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

    /* ------------------- Funtions used for invariant testing ------------------ */

    modifier useActor(uint256 actorIndexSeed) {
        console.log("bound actor ID");
        _currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    function adjustDivisorTest(uint256 newDivisor) external {
        if (_divisor == MIN_DIVISOR) {
            return;
        }
        console.log("bound divisor");
        newDivisor = bound(newDivisor, MIN_DIVISOR, _divisor - 1);
        emit DivisorAdjusted(_divisor, newDivisor);
        _divisor = newDivisor;
    }

    function mintTest(uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        if (totalSupply() == maxTokens()) {
            return;
        }
        console.log("bound mint value");
        value = bound(value, 1, maxTokens() - totalSupply());
        uint256 valueShares = value * _divisor;
        totalSharesSum += valueShares;
        shares[_currentActor] += valueShares;
        _mint(_currentActor, value);
    }

    function burnTest(uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        if (balanceOf(_currentActor) == 0) {
            return;
        }
        console.log("bound burn value");
        value = bound(value, 1, balanceOf(_currentActor));
        uint256 valueShares = value * _divisor;
        totalSharesSum -= valueShares;
        shares[_currentActor] -= valueShares;
        _burn(_currentActor, value);
    }

    function transferTest(uint256 actorTo, uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        console.log("bound 'to' actor ID");
        address to = actors[bound(actorTo, 0, actors.length - 1)];
        if (balanceOf(_currentActor) == 0) {
            return;
        }
        console.log("bound transfer value");
        value = bound(value, 1, balanceOf(_currentActor));
        uint256 valueShares = value * _divisor;
        if (valueShares > shares[_currentActor]) {
            valueShares = shares[_currentActor];
        }

        shares[_currentActor] -= valueShares;
        shares[to] += valueShares;
        _transfer(_currentActor, to, value);
    }
}
