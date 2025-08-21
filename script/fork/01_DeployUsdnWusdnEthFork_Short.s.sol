// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MockChainlinkOnChain } from "../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { DeployUsdnWusdnEth } from "../01_DeployUsdnWusdnEth.s.sol";

import { LiquidationRewardsManagerWusdn } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";

import { WusdnToEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { MockWstEthOracleMiddlewareWithPyth } from
    "../../src/OracleMiddleware/mock/MockWstEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnNoRebase } from "../../src/Usdn/UsdnNoRebase.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { PriceInfo } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract DeployUsdnWusdnFork is DeployUsdnWusdnEth {
    address immutable CHAINLINK_ETH_PRICE_MOCKED = address(new MockChainlinkOnChain());
    uint256 price = 3000 ether;

    constructor() DeployUsdnWusdnEth() {
        UNDERLYING_ASSET = IWusdn(vm.envOr("UNDERLYING_ADDRESS_SHORTDN", address(WUSDN)));
        price = vm.envOr("START_PRICE_SHORTDN", price);
    }

    function preRunAndRun()
        external
        returns (
            WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_,
            LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn_,
            Rebalancer rebalancer_,
            UsdnNoRebase usdnNoRebase_,
            IUsdnProtocol usdnProtocol_
        )
    {
        mockOraclePrice();
        (wusdnToEthOracleMiddleware_, liquidationRewardsManagerWusdn_, rebalancer_, usdnNoRebase_, usdnProtocol_) =
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
            new WusdnToEthOracleMiddlewareWithPyth(
                PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WUSDN.USDN()), CHAINLINK_PRICE_VALIDITY
            )
        );
        PriceInfo memory priceInfo = PriceInfo({ price: price, neutralPrice: price, timestamp: block.timestamp });
        vm.mockCall(
            computedMiddlewareAddress,
            abi.encodeWithSelector(WusdnToEthOracleMiddlewareWithPyth.parseAndValidatePrice.selector),
            abi.encode(priceInfo)
        );
    }

    function setPeripheralContracts(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();

        MockWstEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_ = new MockWstEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(UNDERLYING_ASSET), CHAINLINK_PRICE_VALIDITY
        );
        wusdnToEthOracleMiddleware_.setVerifySignature(false);
        wusdnToEthOracleMiddleware_.setWstethMockedPrice(price);
        usdnProtocol.setOracleMiddleware(wusdnToEthOracleMiddleware_);

        vm.stopBroadcast();
    }
}
