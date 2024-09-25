// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolInvariantSafeFixture } from "./utils/Fixtures.sol";

contract TestUsdnProtocolInvariantsSafe is UsdnProtocolInvariantSafeFixture {
    function setUp() public override {
        super.setUp();
        vm.deal(address(protocol), 100_000 ether); // for security deposits and oracle payments

        string[] memory artifacts = new string[](1);
        artifacts[0] = "test/invariant/UsdnProtocol/utils/Handlers.sol:UsdnProtocolSafeHandler";
        targetInterface(FuzzInterface({ addr: address(protocol), artifacts: artifacts }));
        bytes4[] memory protocolSelectors = new bytes4[](2);
        protocolSelectors[0] = protocol.mine.selector;
        protocolSelectors[1] = protocol.initiateDepositTest.selector;
        targetSelector(FuzzSelector({ addr: address(protocol), selectors: protocolSelectors }));

        targetContract(address(oracleMiddleware));
        bytes4[] memory oracleSelectors = new bytes4[](1);
        oracleSelectors[0] = oracleMiddleware.updatePrice.selector;
        targetSelector(FuzzSelector({ addr: address(oracleMiddleware), selectors: oracleSelectors }));

        targetContract(address(usdn));
        bytes4[] memory usdnSelectors = new bytes4[](5);
        usdnSelectors[0] = usdn.rebaseTest.selector;
        usdnSelectors[1] = usdn.burnTest.selector;
        usdnSelectors[2] = usdn.transferTest.selector;
        usdnSelectors[3] = usdn.burnSharesTest.selector;
        usdnSelectors[4] = usdn.transferSharesTest.selector;
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
