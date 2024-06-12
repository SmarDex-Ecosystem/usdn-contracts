// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
    uint256 _securityDeposit;
    uint256 ts1;

    function setUp() public {
        _setUp();
        // set 4 pending actions
        ts1 = block.timestamp;
        _securityDeposit = protocol.getSecurityDepositValue();
        // 1. initiateDeposit
        uint256 openPositionAmount = 2 ether;
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        sdex.approve(address(protocol), type(uint256).max);
        protocol.initiateDeposit{ value: _securityDeposit }(0.1 ether, USER_2, USER_1, "", EMPTY_PREVIOUS_DATA);
        // 2. initiateWithdrawal
        uint256 withdrawAmount = usdn.sharesOf(DEPLOYER) / 100;
        vm.prank(DEPLOYER);
        usdn.transferShares(address(this), withdrawAmount);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal{ value: _securityDeposit }(
            uint128(withdrawAmount), USER_2, USER_2, "", EMPTY_PREVIOUS_DATA
        );
        // 3. initiateOpenPosition
        uint256 desiredLiquidation = 2500 ether;
        protocol.initiateOpenPosition{ value: _securityDeposit }(
            uint128(openPositionAmount), uint128(desiredLiquidation), address(this), USER_3, "", EMPTY_PREVIOUS_DATA
        );
        // 4. initiateClosePosition
        (, PositionId memory posId) = protocol.initiateOpenPosition{ value: _securityDeposit }(
            uint128(openPositionAmount),
            uint128(desiredLiquidation),
            address(this),
            payable(address(this)),
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay(); // to be realistic because not mandatory
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: validationCost }(payable(this), data, EMPTY_PREVIOUS_DATA);
        protocol.initiateClosePosition{ value: _securityDeposit }(
            posId, uint128(openPositionAmount), USER_1, USER_4, "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Validate pending actions through the router
     * @custom:given The protocol has 4 pending actions
     * @custom:when The user Validate pending actions through the router
     * @custom:then Validate pending actions successfully
     */
    function test_ForkValidatePendingActions() public {
        vm.makePersistent(address(protocol));
        vm.makePersistent(address(router));
        vm.makePersistent(address(oracleMiddleware));
        vm.makePersistent(address(usdn));
        vm.makePersistent(address(wstETH));

        // initial fork roll to skip 20 minutes
        vm.rollFork(block.number + 100);

        // set the search range
        uint256 startBlock = block.number;
        uint256 endBlock = block.number + 300;

        (uint80 roundId,,) = getNextChainlinkPriceAfterTimestamp(ts1, startBlock, endBlock);

        // prepare data for the validation
        bytes memory data = abi.encode(roundId);
        bytes[] memory priceData = new bytes[](4);
        for (uint256 i = 0; i < 4; i++) {
            priceData[i] = data;
        }
        (, uint128[] memory newRawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(newRawIndices.length, 4, "newRawIndices.length");
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: priceData, rawIndices: newRawIndices });
        uint256 ethBalanceBefore = address(router).balance;

        // validating actionable pending actions through the router
        bytes memory commands = abi.encodePacked(uint8(Commands.VALIDATE_PENDING));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(previousActionsData, 4, 0);
        router.execute{ value: 0 }(commands, inputs);

        assertEq(address(router).balance, ethBalanceBefore + _securityDeposit * 4, "ether balance");
    }

    receive() external payable { }
}
