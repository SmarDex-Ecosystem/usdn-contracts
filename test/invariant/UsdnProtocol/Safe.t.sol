// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocolInvariantSafeFixture } from "./utils/Fixtures.sol";
import { console } from "forge-std/console.sol";

contract TestUsdnProtocolInvariantsSafe is UsdnProtocolInvariantSafeFixture {
    function setUp() public override {
        super.setUp();

        string[] memory artifacts = new string[](1);
        artifacts[0] = "test/invariant/UsdnProtocol/utils/handlers/UsdnProtocolSafeHandler.sol:UsdnProtocolSafeHandler";
        targetInterface(FuzzInterface({ addr: address(protocol), artifacts: artifacts }));

        bytes4[] memory protocolSelectors = new bytes4[](9);
        protocolSelectors[0] = protocol.mine.selector;
        protocolSelectors[1] = protocol.initiateDepositTest.selector;
        protocolSelectors[2] = protocol.validateDepositTest.selector;
        protocolSelectors[3] = protocol.initiateWithdrawalTest.selector;
        protocolSelectors[4] = protocol.validateWithdrawalTest.selector;
        protocolSelectors[5] = protocol.validateOpenPositionTest.selector;
        // protocolSelectors[7] = protocol.initiateClosePositionTest.selector;
        protocolSelectors[6] = protocol.validateClosePositionTest.selector;
        protocolSelectors[7] = protocol.validateActionablePendingActionsTest.selector;
        protocolSelectors[8] = protocol.liquidateTest.selector;
        // protocolSelectors[5] = protocol.initiateOpenPositionTest.selector;

        // protocolSelectors[9] = protocol.adminFunctionsTest.selector;

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

    function invariant_securityDeposit() public view {
        uint64 securityDeposit = protocol.getSecurityDepositValue();
        assertLe(securityDeposit, 2 ether, "Security deposit should not exceed maximum");
    }

    function invariant_totalSharesMatchTokens() public view {
        uint256 totalShares = usdn.totalShares();
        uint256 totalSupply = usdn.totalSupply();
        assertGe(totalSupply, 0, "Total supply should be non-negative");
        assertGe(totalShares, 0, "Total shares should be non-negative");

        if (usdn.divisor() == 1) {
            assertEq(totalSupply, totalShares, "When divisor is 1, supply should equal shares");
        }
    }

    function invariant_feeBounds() public view {
        uint16 protocolFeeBps = protocol.getProtocolFeeBps();
        uint16 positionFeeBps = protocol.getPositionFeeBps();
        uint16 vaultFeeBps = protocol.getVaultFeeBps();

        assertLe(protocolFeeBps, 1000, "Protocol fee should not exceed 10%");
        assertLe(positionFeeBps, 10_000, "Position fee should not exceed 100%");
        assertLe(vaultFeeBps, 10_000, "Vault fee should not exceed 100%");
    }

    function invariant_divisorAboveMinimum() public view {
        uint256 currentDivisor = usdn.divisor();
        uint256 MIN_DIVISOR = usdn.MIN_DIVISOR();

        assertGt(currentDivisor, MIN_DIVISOR, "Current divisor should never equal the MIN_DIVISOR");
    }
}
