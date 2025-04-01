// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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
    int128 internal constant LOW_LATENCY_PRICE = 2000 ether;
    int128 internal constant CHAINLINK_PRICE = 3000 ether;
    uint256 internal constant TOKENS_AMOUNT = 1000 ether;
    uint256 internal snapshotId;
    uint256 internal validationCost;
    bool internal success;

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
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        mockChainlinkOnChain.setLastPrice(CHAINLINK_PRICE / 1e10);
        vm.stopPrank();

        vm.startPrank(USER_1);

        success = protocol.initiateDeposit{ value: securityDeposit }(
            BASE_AMOUNT, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );
        assertTrue(success, "The initiate deposit must be successful");

        _waitDelay();

        // adjust payload
        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        report.expiresAt = uint32(block.timestamp);
        report.price = int192(CHAINLINK_PRICE);
        report.ask = int192(CHAINLINK_PRICE) + 1;
        report.bid = int192(CHAINLINK_PRICE) - 1;
        (, payload) = _encodeReport(report);

        validationCost = oracleMiddleware.validationCost(payload, Types.ProtocolAction.ValidateDeposit);
        success = protocol.validateDeposit{ value: validationCost }(USER_1, payload, EMPTY_PREVIOUS_DATA);

        assertTrue(success, "The validate deposit must be successful");

        (, posId) = protocol.initiateOpenPosition{ value: securityDeposit }(
            uint128(protocol.getMinLongPosition()),
            uint128(LOW_LATENCY_PRICE * 11 / 10),
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            USER_1,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        // adjust payload
        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        report.expiresAt = uint32(block.timestamp);
        (, payload) = _encodeReport(report);

        validationCost = oracleMiddleware.validationCost(payload, Types.ProtocolAction.ValidateOpenPosition);
        (LongActionOutcome outcome,) =
            protocol.validateOpenPosition{ value: validationCost }(USER_1, payload, EMPTY_PREVIOUS_DATA);

        assertTrue(outcome == LongActionOutcome.Processed, "The validate open must be processed");

        vm.stopPrank();

        skip(25 minutes);

        report.validFromTimestamp = uint32(block.timestamp);
        report.observationsTimestamp = uint32(block.timestamp);
        report.expiresAt = uint32(block.timestamp + 1 hours);
        report.price = int192(LOW_LATENCY_PRICE);
        report.ask = int192(LOW_LATENCY_PRICE) + 1;
        report.bid = int192(LOW_LATENCY_PRICE) - 1;
        (, payload) = _encodeReport(report);

        vm.startPrank(DEPLOYER);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        vm.stopPrank();

        snapshotId = vm.snapshotState();
    }

    /**
     * @custom:scenario Test the potential profit a user could make when using an outdated Chainlink price
     * to initiate a deposit with pending liquidations that won't be triggered until validation,
     * and then using a fresh Pyth price during initialization, which will trigger the liquidation
     * @custom:when The user validates the deposit
     * @custom:then The user should not make a profit
     */
    function test_ProfitableDeposit() public {
        uint256 usdnBalanceWithArbitrage = _testWithOracleArbitrage();

        vm.revertToState(snapshotId);
        uint256 usdnBalanceWithoutArbitrage = _testWithoutOracleArbitrage();

        assertLt(
            usdnBalanceWithArbitrage,
            usdnBalanceWithoutArbitrage,
            "User shouldn't made usdn profit with oracle arbitrage"
        );
    }

    /// @notice Test a user deposit action arbitrage between the pyth price and an outdated higher chainlink price
    function _testWithOracleArbitrage() internal returns (uint256 usdnBalance_) {
        success = protocol.initiateDeposit{ value: securityDeposit }(
            BASE_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The initiate deposit with arbitrage must be successful");
        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion, "User position tick should not be liquidated");

        _waitDelay();

        // adjust payload
        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        (, payload) = _encodeReport(report);

        validationCost = oracleMiddleware.validationCost(payload, Types.ProtocolAction.ValidateDeposit);
        success = protocol.validateDeposit{ value: validationCost }(payable(this), payload, EMPTY_PREVIOUS_DATA);

        assertTrue(success, "The validate deposit with arbitrage must be successful");
        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion + 1, "User position tick should be liquidated");

        usdnBalance_ = usdn.balanceOf(address(this));
    }

    /// @notice Test a user deposit action without arbitrage between pyth and chainlink
    function _testWithoutOracleArbitrage() internal returns (uint256 usdnBalance_) {
        validationCost = oracleMiddleware.validationCost(payload, Types.ProtocolAction.InitiateDeposit);
        success = protocol.initiateDeposit{ value: securityDeposit + validationCost }(
            BASE_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            payload,
            EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The initiate deposit without arbitrage must be successful");
        assertEq(protocol.getTickVersion(posId.tick), posId.tickVersion + 1, "User position tick should be liquidated");

        _waitDelay();

        // adjust payload
        report.validFromTimestamp = uint32(block.timestamp - 1);
        report.observationsTimestamp = uint32(block.timestamp - 1);
        (, payload) = _encodeReport(report);

        validationCost = oracleMiddleware.validationCost(payload, Types.ProtocolAction.ValidateDeposit);
        success = protocol.validateDeposit{ value: validationCost }(payable(this), payload, EMPTY_PREVIOUS_DATA);

        assertTrue(success, "The validate deposit without arbitrage must be successful");

        usdnBalance_ = usdn.balanceOf(address(this));
    }

    receive() external payable { }
}
