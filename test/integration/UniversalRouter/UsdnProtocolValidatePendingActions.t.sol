// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { console2 } from "forge-std/Test.sol";

import { PYTH_ETH_USD } from "test/utils/Constants.sol";
import { DEPLOYER, USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import {
    ProtocolAction,
    PendingAction,
    PreviousActionsData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validate pending actions through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterValidatePendingActions is UniversalRouterBaseFixture {
    using SafeCast for uint256;

    uint256 constant OPEN_POSITION_AMOUNT = 2 ether;
    uint256 constant DESIRED_LIQUIDATION = 2500 ether;
    PositionId internal _posId;
    uint256 _securityDeposit;
    uint256 ts1;

    function setUp() public {
        // set 4 pending actions
        _setUp();
        ts1 = block.timestamp;
        // 1. initiateDeposit
        deal(address(wstETH), address(this), OPEN_POSITION_AMOUNT * 2);
        wstETH.approve(address(protocol), type(uint256).max);
        _securityDeposit = protocol.getSecurityDepositValue();
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        sdex.approve(address(protocol), type(uint256).max);
        protocol.initiateDeposit{ value: _securityDeposit }(0.1 ether, USER_2, USER_1, "", EMPTY_PREVIOUS_DATA);
        // 2. initiateWithdrawal
        uint256 WITHDRAW_AMOUNT = usdn.sharesOf(DEPLOYER) / 100;
        vm.prank(DEPLOYER);
        usdn.transferShares(address(this), WITHDRAW_AMOUNT);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal{ value: _securityDeposit }(
            WITHDRAW_AMOUNT.toUint152(), USER_2, USER_2, "", EMPTY_PREVIOUS_DATA
        );
        // 3. initiateOpenPosition
        protocol.initiateOpenPosition{ value: _securityDeposit }(
            OPEN_POSITION_AMOUNT.toUint128(),
            DESIRED_LIQUIDATION.toUint128(),
            address(this),
            USER_3,
            "",
            EMPTY_PREVIOUS_DATA
        );
        // 4. initiateClosePosition
        (, PositionId memory posId) = protocol.initiateOpenPosition{ value: _securityDeposit }(
            OPEN_POSITION_AMOUNT.toUint128(),
            DESIRED_LIQUIDATION.toUint128(),
            address(this),
            payable(address(this)),
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay(); // to be realistic because not mandatory
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: validationCost }(payable(address(this)), data, EMPTY_PREVIOUS_DATA);
        protocol.initiateClosePosition{ value: _securityDeposit }(
            posId, OPEN_POSITION_AMOUNT.toUint128(), USER_1, USER_4, "", EMPTY_PREVIOUS_DATA
        );
        PendingAction memory action_ = protocol.getUserPendingAction(USER_1);
        assertEq(action_.validator, USER_1, "newRawIndices.length");
    }

    /**
     * @custom:scenario Validate pending actions through the router
     * @custom:given The protocol has 4 pending actions
     * @custom:when The user Validate pending actions through the router
     * @custom:then Validate pending actions successfully
     */
    function test_ForkValidatePendingActions() public {
        uint256 lowLatencyLimit = ts1 + oracleMiddleware.getLowLatencyDelay();
        (uint80 roundId,,, uint256 updatedAt,) = priceFeed.latestRoundData();
        vm.makePersistent(address(protocol));
        vm.makePersistent(address(router));
        vm.makePersistent(address(oracleMiddleware));
        vm.makePersistent(address(usdn));
        vm.makePersistent(address(wstETH));
        vm.rollFork(block.number + 99);
        while (lowLatencyLimit > updatedAt) {
            vm.rollFork(block.number + 10);
            (roundId,,, updatedAt,) = priceFeed.latestRoundData();
        }
        uint256 forkOne = block.number;
        for (uint256 i = 0; i < 10; i++) {
            vm.rollFork(block.number - 1);
            (uint80 newRoundId,,, uint256 newUpdatedAt,) = priceFeed.latestRoundData();
            if (newUpdatedAt >= lowLatencyLimit) {
                roundId = newRoundId;
                updatedAt = newUpdatedAt;
                break;
            }
        }
        vm.rollFork(forkOne);
        skip(protocol.getValidationDeadline());

        (,, uint256 startedAtOne,,) = priceFeed.getRoundData(roundId - 1);
        (,, uint256 startedAtTwo,,) = priceFeed.getRoundData(roundId);
        assertTrue(startedAtOne < lowLatencyLimit, "startedAtOne < lowLatencyLimit");
        assertTrue(startedAtTwo >= lowLatencyLimit, "startedAtTwo >= lowLatencyLimit");

        bytes memory data = abi.encode(roundId);

        bytes[] memory priceData = new bytes[](4);
        priceData[0] = data;
        priceData[1] = priceData[0];
        priceData[2] = priceData[0];
        priceData[3] = priceData[0];
        (, uint128[] memory newRawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(newRawIndices.length, 4, "newRawIndices.length");
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: priceData, rawIndices: newRawIndices });
        uint256 ethBalanceBefore = address(router).balance;

        bytes memory commands = abi.encodePacked(uint8(Commands.VALIDATE_PENDING));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(previousActionsData, 4, 0);
        router.execute{ value: 0 }(commands, inputs);

        assertEq(address(router).balance, ethBalanceBefore + _securityDeposit * 4, "ether balance");
    }

    receive() external payable { }
}
