// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "test/utils/Constants.sol";
import { DEPLOYER } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number
    });
    // previous long init
    uint256[] public prevActionBlock;
    // store created addresses
    address[] public users;

    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;
    uint128 public defaultPosLeverage;
    uint128 public initialLongLeverage;

    function _setUp(SetUpParams memory testParams) public virtual {
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        protocol = new UsdnProtocolHandler(usdn, wstETH, oracleMiddleware, 100); // tick spacing 100 = 1%
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            testParams.initialPrice / 2,
            abi.encode(testParams.initialPrice)
        );
        usdnInitialTotalSupply = usdn.totalSupply();
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0, 0);
        defaultPosLeverage = defaultPos.leverage;
        Position memory firstPos =
            protocol.getLongPosition(protocol.getEffectiveTickForPrice(testParams.initialPrice / 2), 0, 0);
        initialLongLeverage = firstPos.leverage;
        vm.stopPrank();
        params = testParams;

        // initialize x10 EOA addresses with 10K ETH and 10K WSTETH
        createAndFundUsers(10, 10_000 ether);
        // store initial usdn action block number
        prevActionBlock.push(params.initialBlock);
        // increment 1 block
        vm.roll(params.initialBlock + 1);
    }

    function test_setUp() public {
        _setUp(DEFAULT_PARAMS);
        assertGt(protocol.tickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(
            wstETH.balanceOf(address(protocol)), params.initialDeposit + params.initialLong, "wstETH protocol balance"
        );
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        uint256 usdnTotalSupply = uint256(params.initialDeposit) * params.initialPrice / 10 ** 18;
        assertEq(usdnTotalSupply, usdnInitialTotalSupply, "usdn total supply");
        assertEq(usdn.balanceOf(DEPLOYER), usdnTotalSupply - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0, 0);
        assertEq(defaultPos.leverage, 1_000_000_000_000_000_005_039, "default pos leverage");
        assertEq(defaultPos.timestamp, block.timestamp, "default pos timestamp");
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS(), "default pos user");
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT(), "default pos amount");
        assertEq(defaultPos.startPrice, params.initialPrice, "default pos start price");
        Position memory firstPos =
            protocol.getLongPosition(protocol.getEffectiveTickForPrice(params.initialPrice / 2), 0, 0);
        assertEq(firstPos.leverage, 1_983_994_053_940_692_631_258, "first pos leverage");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, params.initialLong - protocol.FIRST_LONG_AMOUNT(), "first pos amount");
        assertEq(firstPos.startPrice, params.initialPrice, "first pos start price");
    }

    // create x funded addresses with ETH and underlying
    function createAndFundUsers(uint256 userCount, uint256 initialBalance) public {
        // user memory
        address[] memory _users = new address[](userCount);

        for (uint256 i; i < userCount; i++) {
            // user address from private key i + 1
            _users[i] = vm.addr(i + 1);

            // fund eth
            vm.deal(_users[i], initialBalance * 2);

            // fund wsteth
            vm.startPrank(_users[i]);
            (bool success,) = address(wstETH).call{ value: initialBalance }("");
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
        returns (int24 tick_, uint256 tickVersion_)
    {
        uint256 count = _users.length;

        for (uint256 i; i < count; i++) {
            (uint128 currentPrice, bytes memory priceData) = getPriceInfo(block.number);
            // liquidation target price -15%
            uint128 liquidationTargetPriceUint = currentPrice * 85 / 100;

            vm.startPrank(_users[i]);
            // initiate open position
            (tick_, tickVersion_,) = protocol.initiateOpenPosition(refAmount, liquidationTargetPriceUint, priceData, "");

            // if auto validate true
            if (autoValidate) {
                // auto validate open position
                protocol.validateOpenPosition(priceData, priceData);
            }
            vm.stopPrank();
        }
    }

    // get encoded price to simulate a price drawdown according to
    // block number currently 1% down per block from initial price
    function getPriceInfo(uint256 blockNumber) public view returns (uint128 price_, bytes memory data_) {
        // check correct block
        require(blockNumber + 1 > params.initialBlock, "unallowed block");
        // diff block + 1
        uint256 diffBlocks = blockNumber + 1 - params.initialBlock;
        // check correct diffBlocks
        require(diffBlocks < 100, "block number too far");
        // price = initial price - (n x diff block)%
        price_ = uint128(params.initialPrice - (params.initialPrice * diffBlocks / 100));
        // encode price
        data_ = abi.encode(price_);
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
