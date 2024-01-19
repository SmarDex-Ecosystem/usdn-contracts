// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IUsdnProtocolErrors, IUsdnProtocolEvents, Position } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { Usdn } from "src/Usdn.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    uint128 public constant INITIAL_DEPOSIT = 10 ether;
    uint128 public constant INITIAL_LONG = 5 ether;
    uint128 public constant INITIAL_PRICE = 2000 ether; // 2000 USD per wstETH
    // initial wsteth price randomly setup at $2630
    uint128 public constant WSTETH_INITIAL_PRICE = 2630 ether;
    // initial block
    uint256 public initialBlock;
    // previous long init
    uint256[] public prevActionBlock;
    // store created addresses
    address[] public users;

    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;

    function setUp() public virtual {
        vm.warp(1_704_092_400); // 2024-01-01 07:00:00 UTC
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 100); // tick spacing 100 = 1%
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            INITIAL_DEPOSIT,
            INITIAL_LONG,
            protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2),
            abi.encode(INITIAL_PRICE)
        );
        usdnInitialTotalSupply = usdn.totalSupply();
        vm.stopPrank();

        // initialize x10 EOA addresses with 10K ETH and 10K WSTETH
        createAndFundUsers(10, 10_000 ether);
        // store initial block
        initialBlock = block.number;
        // store initial usdn action block number
        prevActionBlock.push(initialBlock);
        // increment 1 block
        vm.roll(initialBlock + 1);
    }

    function test_setUp() public {
        assertGt(protocol.tickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_DEPOSIT + INITIAL_LONG, "wstETH protocol balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        uint256 usdnTotalSupply = uint256(INITIAL_DEPOSIT) * INITIAL_PRICE / 10 ** 18;
        assertEq(usdnTotalSupply, usdnInitialTotalSupply, "usdn total supply");
        assertEq(usdn.balanceOf(DEPLOYER), usdnTotalSupply - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0);
        assertEq(defaultPos.leverage, 1 gwei, "default pos leverage");
        assertEq(defaultPos.timestamp, block.timestamp, "default pos timestamp");
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS(), "default pos user");
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT(), "default pos amount");
        assertEq(defaultPos.startPrice, INITIAL_PRICE, "default pos start price");
        Position memory firstPos = protocol.getLongPosition(protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2), 0);
        assertEq(firstPos.leverage, 1_983_994_053, "first pos leverage");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, INITIAL_LONG - protocol.FIRST_LONG_AMOUNT(), "first pos amount");
        assertEq(firstPos.startPrice, INITIAL_PRICE, "first pos start price");
    }

    // create x funded addresses with ETH and underlying
    function createAndFundUsers(uint256 _userCount, uint256 _initialBalance) public {
        // user memory
        address[] memory _users = new address[](_userCount);

        for (uint256 i; i < _userCount; i++) {
            // user address from private key i + 1
            _users[i] = vm.addr(i + 1);

            // fund eth
            vm.deal(_users[i], _initialBalance * 2);

            // fund wsteth
            vm.startPrank(_users[i]);
            (bool success,) = address(wstETH).call{ value: _initialBalance }("");
            require(success, "swap asset error");
            wstETH.approve(address(protocol), type(uint256).max);

            assertTrue(wstETH.balanceOf(_users[i]) != 0, "user with empty wallet");
            vm.stopPrank();
        }
        // store users
        users = _users;
    }

    // mock initiate open positions for x users
    function mockInitiateOpenPosition(uint96 refAmount, bool autoValidate, address[] memory _users)
        public
        returns (int24 _tick)
    {
        uint256 count = _users.length;

        for (uint256 i; i < count; i++) {
            (uint128 currentPrice, bytes memory priceData) = getPriceInfo(block.number);
            // uint128 currentPriceUint = uint128(abi.decode(currentPrice, (uint256)));
            // liquidation target price -15%
            uint128 liquidationTargetPriceUint = currentPrice - (currentPrice * 15 / 100);
            // effective tick for target price
            _tick = protocol.getEffectiveTickForPrice(liquidationTargetPriceUint);

            vm.startPrank(_users[i]);
            // initiate open position
            protocol.initiateOpenPosition(refAmount, _tick, priceData, "");

            // if auto validate true
            if (autoValidate) {
                // auto validate open position
                protocol.validateOpenPosition(priceData, priceData);
            }
            vm.stopPrank();
        }
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

    // users memory array
    function getUsers(uint256 length) public view returns (address[] memory) {
        require(length <= users.length, "wrong length");
        address[] memory _users = new address[](length);

        for (uint256 i; i < length; i++) {
            _users[i] = users[i];
        }

        return _users;
    }
}
