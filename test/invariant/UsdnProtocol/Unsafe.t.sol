// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolInvariantFixture } from "./utils/Fixtures.sol";

contract FoundryFuzzingTest is UsdnProtocolInvariantFixture {
    function setUp() public override {
        super.setUp();

        targetContract(address(protocol));
        bytes4[] memory protocolSelectors = new bytes4[](1);
        protocolSelectors[0] = protocol.mine.selector;
        targetArtifactSelector(
            FuzzArtifactSelector({
                artifact: "test/invariant/UsdnProtocol/utils/Handlers.sol:UsdnProtocolHandler",
                selectors: protocolSelectors
            })
        );

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
}
