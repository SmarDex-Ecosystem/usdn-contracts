// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER, SET_PROTOCOL_PARAMS_MANAGER, USER_1 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test whether there is a profit in these two situations, with the same configuration:
 * Positions to be liquidated, but Chainlink's price does not yet allow this
 * No liquidation during the initiate, then liquidation during the validate
 *
 * Positions to be liquidated, liquidation during initiate and normal validate
 * @custom:background Given a protocol initialized with default params
 */
contract TestUsdnProtocolProfitableDeposit is UsdnProtocolBaseIntegrationFixture {
    uint256 internal securityDeposit;
    Types.PositionId internal posId;
    uint128 internal constant BASE_AMOUNT = 0.5 ether;
    int256 internal wstethUpdatedPrice;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);
        securityDeposit = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(USER_1, 1_000_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(address(this), 1_000_000 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 100_000_000_000 ether, address(protocol), type(uint256).max);

        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setMinLongPosition(0);

        skip(25 minutes);

        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPrice(
            int256(wstETH.getWstETHByStETH(uint256(int256(uint256(params.initialPrice / 1e10)))))
        );
        mockChainlinkOnChain.setLastPublishTime(block.timestamp - 10 minutes);
        (, int256 chainlinkPrice,,,) = mockChainlinkOnChain.latestRoundData();
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(chainlinkPrice));
        vm.stopPrank();

        bool success;
        vm.startPrank(USER_1);
        (success, posId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            BASE_AMOUNT,
            uint128(wstETH.getStETHByWstETH(uint256(chainlinkPrice * 1e10))) * 9 / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            USER_1,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        vm.stopPrank();

        assertTrue(success, "Position should be initiated");

        wstethUpdatedPrice =
            int256(wstETH.getWstETHByStETH(uint256(int256(uint256(params.initialLiqPrice * 11 / 10 / 1e10)))));

        skip(25 minutes);
    }

    /**
     * @custom:scenario Test the potential profit of a user deposit with a pending liquidation by doing arbitrage
     * between oracles
     * @custom:when The user validates a deposit
     * @custom:then He shouldn't make profit
     */
    function test_ProfitableDeposit() public {
        uint256 withArbitrageValue = _testWithOracleArbitrage();

        setUp();
        uint256 withoutArbitrageValue = _testWithoutOracleArbitrage();

        int256 arbitrageProfit = int256(withArbitrageValue) - int256(withoutArbitrageValue);

        emit log_named_decimal_int("Arbitrage profit in $: ", arbitrageProfit, 18);
        assertLt(arbitrageProfit, 0, "User shouldn't made profit with oracle arbitrage");
    }

    receive() external payable { }

    /// @notice Test a user deposit action arbitrage between the pyth price and an outdated higher chainlink price
    function _testWithOracleArbitrage() internal returns (uint256 totalValue_) {
        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp - 10 minutes);
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(wstethUpdatedPrice));
        vm.stopPrank();

        protocol.initiateDeposit{ value: securityDeposit }(
            BASE_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion, "User position tick should not be liquidated");

        _waitDelay();

        protocol.validateDeposit(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);
        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion + 1, "User position tick should be liquidated");

        uint128 lastWstethPrice = protocol.getLastPrice();
        uint256 wstEthValue = wstETH.balanceOf(address(this)) * lastWstethPrice;
        uint256 ethValue = address(this).balance * params.initialLiqPrice * 11 / 10;
        uint256 usdnValue = usdn.balanceOf(address(this)) * protocol.usdnPrice(lastWstethPrice);

        totalValue_ = (wstEthValue + ethValue + usdnValue) / 1e18;
    }

    /// @notice Test a user deposit action without arbitrage between pyth and chainlink
    function _testWithoutOracleArbitrage() internal returns (uint256 totalValue_) {
        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPrice(int256(uint256(wstethUpdatedPrice)));
        mockChainlinkOnChain.setLastPublishTime(block.timestamp - 10 minutes);
        (, int256 chainlinkPrice,,,) = mockChainlinkOnChain.latestRoundData();
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(chainlinkPrice));
        vm.stopPrank();

        protocol.initiateDeposit{ value: securityDeposit }(
            BASE_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion + 1, "User position tick should be liquidated");

        _waitDelay();

        protocol.validateDeposit(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        uint128 lastWstethPrice = protocol.getLastPrice();
        uint256 wstEthValue = wstETH.balanceOf(address(this)) * lastWstethPrice;
        uint256 ethValue = address(this).balance * params.initialLiqPrice * 11 / 10;
        uint256 usdnValue = usdn.balanceOf(address(this)) * protocol.usdnPrice(lastWstethPrice);

        totalValue_ = (wstEthValue + ethValue + usdnValue) / 1e18;
    }
}
