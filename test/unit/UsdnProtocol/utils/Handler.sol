// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";

import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol, Test {
    // initial wsteth price randomly setup at $2630
    uint128 public constant WSTETH_INITIAL_PRICE = 2630 ether;
    // initial block
    uint256 public immutable initialBlock;
    // previous long init
    uint256[] public prevActionBlock;
    // store created addresses
    address[] public users;

    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    {
        // initialize x10 EOA addresses with 10K ETH and 10K WSTETH
        createAndFundUsers(address(asset), 10, 10_000 ether);
        // store initial block
        initialBlock = block.number;
        // store initial usdn action block number
        prevActionBlock.push(initialBlock);
        // increment 1 block
        vm.roll(initialBlock + 1);
    }

    // expose previous action block length
    function prevActionBlockLength() external view returns (uint256) {
        return prevActionBlock.length;
    }

    // expose underlying address
    function underlying() public view returns (IERC20Metadata) {
        return _asset;
    }

    // create x funded addresses with ETH and underlying
    function createAndFundUsers(address _asset, uint256 _userCount, uint256 _initialBalance) public {
        // user memory
        address[] memory _users = new address[](_userCount);

        for (uint256 i; i < _userCount; i++) {
            // user address from private key i + 1
            _users[i] = vm.addr(i + 1);

            // fund eth
            vm.deal(_users[i], _initialBalance * 2);

            // fund wsteth
            vm.prank(_users[i]);
            (bool success,) = _asset.call{ value: _initialBalance }("");
            require(success, "swap asset error");
        }
        // store users
        users = _users;
    }

    // get current user count
    function userCount() public view returns (uint256) {
        return users.length;
    }

    // store previous action block number
    // useful to retrieve a price at a block number
    function setPrevActionBlock(uint256 _blockNumber) public {
        prevActionBlock.push(_blockNumber);
    }

    // get encoded price
    // to simulate a price drawdown
    // according to block number
    // currently 1% down per block
    // from initial price
    function getPriceInfo(uint256 blockNumber) public view returns (uint128 price, bytes memory data) {
        // check correct block
        require(blockNumber + 1 > initialBlock, "unallowed block");
        // diff block + 1
        uint256 diffBlocks = blockNumber + 1 - initialBlock;
        // check correct diffBlocks
        require(diffBlocks < 100, "block number too far");
        // price = initial price - (n x diff block)%
        price = uint128(WSTETH_INITIAL_PRICE - (WSTETH_INITIAL_PRICE * diffBlocks / 100));
        // encode price
        data = abi.encode(price);
    }

    // mock initiate open positions for x users
    // users must be created with createAndFundUsers()
    function mockInitiateOpenPosition(uint96 refAmount, bool autoValidate, address[] memory _users)
        external
        returns (int24 _tick)
    {
        uint256 count = _users.length;

        for (uint256 i; i < count; i++) {
            address user = _users[i];
            vm.startPrank(user);
            _asset.approve(address(this), type(uint256).max);

            (uint128 currentPrice, bytes memory priceData) = getPriceInfo(block.number);
            // uint128 currentPriceUint = uint128(abi.decode(currentPrice, (uint256)));
            // liquidation target price -15%
            uint128 liquidationTargetPriceUint = currentPrice - (currentPrice * 15 / 100);
            // effective tick for target price
            _tick = getEffectiveTickForPrice(liquidationTargetPriceUint);

            // initiate open position
            this.initiateOpenPosition(refAmount, _tick, priceData, "");

            // if auto validate true
            if (autoValidate) {
                // auto validate open position
                this.validateOpenPosition(priceData, priceData);
            }
        }

        // store prev action bloc number
        setPrevActionBlock(block.number);
    }

    // users memory array
    function getUsers(uint256 length) external view returns (address[] memory) {
        require(length <= users.length, "wrong length");
        address[] memory _users = new address[](length);

        for (uint256 i; i < length; i++) {
            _users[i] = users[i];
        }

        return _users;
    }

    // tick version
    function tickVersion(int24 _tick) external view returns (uint256) {
        return _tickVersion[_tick];
    }

    // total expo
    function totalExpo() external view returns (uint256) {
        return _totalExpo;
    }

    // tick hash
    function tickHash(int24 tick) external view returns (bytes32) {
        return _tickHash(tick);
    }

    // total expo by tick
    function totalExpoByTick(int24 tick) external view returns (uint256) {
        return _totalExpoByTick[_tickHash(tick)];
    }

    // long positions length
    function longPositionsLength(int24 tick) external view returns (uint256) {
        return _longPositions[_tickHash(tick)].length;
    }

    // positions in tick
    function positionsInTick(int24 tick) external view returns (uint256) {
        return _positionsInTick[_tickHash(tick)];
    }

    // max initialized tick
    function maxInitializedTick() external view returns (int24) {
        return _maxInitializedTick;
    }

    // total long position
    function totalLongPositions() external view returns (uint256) {
        return _totalLongPositions;
    }
}
