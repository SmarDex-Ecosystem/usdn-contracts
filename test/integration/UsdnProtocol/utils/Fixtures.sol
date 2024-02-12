// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER } from "test/utils/Constants.sol";
import { WstethIntegrationFixture } from "test/integration/OracleMiddleware/utils/Fixtures.sol";

import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Usdn } from "src/Usdn.sol";

contract UsdnProtocolBaseIntegrationFixture is WstethIntegrationFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number
    });

    Usdn public usdn;
    UsdnProtocol public protocol;

    modifier reSetUp() override {
        _setUp(params);
        _;
    }

    function _setUp(SetUpParams memory testParams) public virtual {
        super.setUp();
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        (bool success,) = address(WST_ETH).call{ value: 100_000 ether }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));
        protocol = new UsdnProtocol(usdn, WST_ETH, wstethMiddleware, 100); // tick spacing 100 = 1%
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        WST_ETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            testParams.initialPrice / 2,
            abi.encode(testParams.initialPrice)
        );
        vm.stopPrank();
        params = testParams;
    }
}
