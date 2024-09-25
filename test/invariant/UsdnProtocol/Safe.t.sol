// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolInvariantSafeFixture } from "./utils/Fixtures.sol";

contract FoundryFuzzingTest is UsdnProtocolInvariantSafeFixture {
    function setUp() public override {
        super.setUp();

        targetContract(address(protocol));
        bytes4[] memory protocolSelectors = new bytes4[](1);
        protocolSelectors[0] = protocol.initiateDeposit.selector; // TODO: user handler methods
        targetSelector(FuzzSelector({ addr: address(protocol), selectors: protocolSelectors }));

        targetContract(address(usdn));
        bytes4[] memory usdnSelectors = new bytes4[](7);
        usdnSelectors[0] = usdn.rebaseTest.selector;
        usdnSelectors[2] = usdn.burnTest.selector;
        usdnSelectors[3] = usdn.transferTest.selector;
        usdnSelectors[5] = usdn.burnSharesTest.selector;
        usdnSelectors[6] = usdn.transferSharesTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: usdnSelectors }));

        for (uint256 i = 0; i < protocol.SENDERS_LENGTH(); i++) {
            targetSender(protocol.senders(i));
        }
    }
}
