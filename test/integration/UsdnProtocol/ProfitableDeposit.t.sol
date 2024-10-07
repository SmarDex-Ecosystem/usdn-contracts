// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { DEPLOYER, USER_1 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test whether there is a profit in the following two situations, with the same configuration:
 * 1. Positions are to be liquidated, but Chainlink's price does not yet allow liquidation.
 *    - No liquidation during the initiation, but liquidation occurs during validation.
 *
 * 2. Positions are to be liquidated, and liquidation occurs during initiation with a normal validation.
 */
contract TestUsdnProtocolProfitableDeposit is UsdnProtocolBaseIntegrationFixture {
    uint256 internal securityDeposit;
    Types.PositionId internal posId;
    uint128 internal constant BASE_AMOUNT = 3 ether;
    int128 internal constant PYTH_PRICE = 1500 ether;
    int128 internal constant INITIAL_PRICE = 2000 ether;
    int128 internal constant CHAINLINK_PRICE = 2500 ether;
    uint256 internal constant TOKENS_AMOUNT = 1000 ether;
    uint256 snapshotId;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialLong = 200 ether;
        _setUp(params);
        securityDeposit = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(USER_1, TOKENS_AMOUNT, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(address(this), TOKENS_AMOUNT, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), TOKENS_AMOUNT, address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_1, TOKENS_AMOUNT, address(protocol), type(uint256).max);

        skip(25 minutes);

        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp - 10 minutes);
        mockChainlinkOnChain.setLastPrice(INITIAL_PRICE / 1e10);
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(INITIAL_PRICE / 1e10));
        vm.stopPrank();

        vm.startPrank(USER_1);

        protocol.initiateDeposit{ value: securityDeposit }(
            BASE_AMOUNT, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateDeposit(USER_1, MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        (, posId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            uint128(protocol.getMinLongPosition()),
            uint128(wstETH.getStETHByWstETH(uint128(PYTH_PRICE))) * 11 / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            USER_1,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        protocol.validateOpenPosition(USER_1, MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        vm.stopPrank();

        skip(25 minutes);

        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp - 10 minutes);
        mockChainlinkOnChain.setLastPrice(CHAINLINK_PRICE / 1e10);
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(PYTH_PRICE / 1e10));
        vm.stopPrank();

        snapshotId = vm.snapshot();
    }

    /**
     * @custom:scenario Test the potential profit of a user deposit with a pending liquidation by doing arbitrage
     * between oracles
     * @custom:when The user validates a deposit
     * @custom:then He shouldn't make profit
     */
    function test_ProfitableDeposit() public {
        uint256 usdnBalanceWithArbitrage = _testWithOracleArbitrage();

        vm.revertTo(snapshotId);
        uint256 usdnBalanceWithoutArbitrage = _testWithoutOracleArbitrage();

        assertLt(
            int256(usdnBalanceWithArbitrage) - int256(usdnBalanceWithoutArbitrage),
            0,
            "User shouldn't made usdn profit with oracle arbitrage"
        );
    }

    /// @notice Test a user deposit action arbitrage between the pyth price and an outdated higher chainlink price
    function _testWithOracleArbitrage() internal returns (uint256 usdnBalance_) {
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

        usdnBalance_ = usdn.balanceOf(address(this));
    }

    /// @notice Test a user deposit action without arbitrage between pyth and chainlink
    function _testWithoutOracleArbitrage() internal returns (uint256 usdnBalance_) {
        protocol.initiateDeposit{
            value: securityDeposit + oracleMiddleware.validationCost(MOCK_PYTH_DATA, Types.ProtocolAction.InitiateDeposit)
        }(
            BASE_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA
        );

        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion + 1, "User position tick should be liquidated");

        _waitDelay();

        protocol.validateDeposit(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        usdnBalance_ = usdn.balanceOf(address(this));
    }

    receive() external payable { }
}
