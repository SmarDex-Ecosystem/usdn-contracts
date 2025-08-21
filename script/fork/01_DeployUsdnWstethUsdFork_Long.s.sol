// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MockChainlinkOnChain } from "../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { DeployUsdnWstethUsd } from "../01_DeployUsdnWstethUsd.s.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";

import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { MockWstEthOracleMiddlewareWithPyth } from
    "../../src/OracleMiddleware/mock/MockWstEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { PriceInfo } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract DeployUsdnWstethFork is DeployUsdnWstethUsd {
    address immutable CHAINLINK_ETH_PRICE_MOCKED = address(new MockChainlinkOnChain());
    uint256 price = 3000 ether;

    constructor() DeployUsdnWstethUsd() {
        UNDERLYING_ASSET = IWstETH(vm.envOr("UNDERLYING_ADDRESS_USDN", address(WSTETH)));
        price = vm.envOr("START_PRICE_USDN", price);
    }

    function preRunAndRun()
        external
        returns (
            WstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_,
            LiquidationRewardsManagerWstEth liquidationRewardsManagerWstEth_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            IWusdn wusdn_,
            IUsdnProtocol usdnProtocol_
        )
    {
        mockOraclePrice();
        (wstEthOracleMiddleware_, liquidationRewardsManagerWstEth_, rebalancer_, usdn_, wusdn_, usdnProtocol_) =
            this.run();
        setRoles(usdnProtocol_);
        setPeripheralContracts(usdnProtocol_);
        vm.clearMockedCalls();
    }

    function setRoles(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, msg.sender);
        vm.stopBroadcast();
        Usdn usdn = Usdn(address(usdnProtocol.getUsdn()));
        vm.startBroadcast();
        vm.startPrank(address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), msg.sender);
        usdn.grantRole(usdn.REBASER_ROLE(), msg.sender);
        vm.stopPrank();
        vm.stopBroadcast();
    }

    function mockOraclePrice() internal {
        address computedMiddlewareAddress = address(
            new WstEthOracleMiddlewareWithPyth(
                PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(UNDERLYING_ASSET), CHAINLINK_PRICE_VALIDITY
            )
        );
        PriceInfo memory priceInfo = PriceInfo({ price: price, neutralPrice: price, timestamp: block.timestamp });
        vm.mockCall(
            computedMiddlewareAddress,
            abi.encodeWithSelector(WstEthOracleMiddlewareWithPyth.parseAndValidatePrice.selector),
            abi.encode(priceInfo)
        );
    }

    function setPeripheralContracts(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();

        MockWstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_ = new MockWstEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS,
            PYTH_ETH_FEED_ID,
            CHAINLINK_ETH_PRICE_MOCKED,
            address(UNDERLYING_ASSET),
            CHAINLINK_PRICE_VALIDITY
        );
        wstEthOracleMiddleware_.setVerifySignature(false);
        wstEthOracleMiddleware_.setWstethMockedPrice(price);
        usdnProtocol.setOracleMiddleware(wstEthOracleMiddleware_);

        vm.stopBroadcast();
    }
}
