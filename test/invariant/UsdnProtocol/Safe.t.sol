// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolInvariantSafeFixture } from "./utils/Fixtures.sol";

contract TestUsdnProtocolInvariantsSafe is UsdnProtocolInvariantSafeFixture {
    function setUp() public override {
        super.setUp();

        string[] memory artifacts = new string[](1);
        artifacts[0] = "test/invariant/UsdnProtocol/utils/handlers/UsdnProtocolSafeHandler.sol:UsdnProtocolSafeHandler";
        targetInterface(FuzzInterface({ addr: address(protocol), artifacts: artifacts }));

        bytes4[] memory protocolSelectors = new bytes4[](11);
        protocolSelectors[0] = protocol.mine.selector;
        protocolSelectors[1] = protocol.initiateDepositTest.selector;
        protocolSelectors[2] = protocol.validateDepositTest.selector;
        protocolSelectors[3] = protocol.initiateWithdrawalTest.selector;
        protocolSelectors[4] = protocol.validateWithdrawalTest.selector;
        protocolSelectors[5] = protocol.initiateOpenPositionTest.selector;
        protocolSelectors[6] = protocol.validateOpenPositionTest.selector;
        protocolSelectors[7] = protocol.initiateClosePositionTest.selector;
        protocolSelectors[8] = protocol.validateClosePositionTest.selector;
        protocolSelectors[9] = protocol.validateActionablePendingActionsTest.selector;
        protocolSelectors[10] = protocol.liquidateTest.selector;

        targetSelector(FuzzSelector({ addr: address(protocol), selectors: protocolSelectors }));
        targetContract(address(protocol));

        targetContract(address(oracleMiddleware));
        bytes4[] memory oracleSelectors = new bytes4[](1);
        oracleSelectors[0] = oracleMiddleware.updatePrice.selector;
        targetSelector(FuzzSelector({ addr: address(oracleMiddleware), selectors: oracleSelectors }));

        targetContract(address(usdn));
        bytes4[] memory usdnSelectors = new bytes4[](2);
        usdnSelectors[0] = usdn.burnSharesTest.selector;
        usdnSelectors[1] = usdn.transferSharesTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: usdnSelectors }));

        address[] memory senders = protocol.senders();
        for (uint256 i = 0; i < senders.length; i++) {
            targetSender(senders[i]);
        }
    }

    function invariant_balance() public view {
        uint256 balanceLong = protocol.getBalanceLong();
        uint256 balanceVault = protocol.getBalanceVault();
        assertGe(wstETH.balanceOf(address(protocol)), balanceLong + balanceVault, "real balance vs total balance");
    }
}
