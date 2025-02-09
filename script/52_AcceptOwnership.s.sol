// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract TransferProtocolOwnership is Script {
    IUsdnProtocol internal _usdnProtocol;
    WstEthOracleMiddleware _wstEthOracleMiddleware;
    LiquidationRewardsManager _liquidationRewardsManager;
    Rebalancer _rebalancer;

    function run() external {
        _handleEnvVariables();

        (address newOwner,) = _usdnProtocol.pendingDefaultAdmin();

        vm.startBroadcast(newOwner);

        _usdnProtocol.acceptDefaultAdminTransfer();
        _wstEthOracleMiddleware.acceptDefaultAdminTransfer();
        _liquidationRewardsManager.acceptOwnership();
        _rebalancer.acceptOwnership();
    }

    function _handleEnvVariables() internal {
        try vm.envAddress("USDN_PROTOCOL_ADDRESS") {
            _usdnProtocol = IUsdnProtocol(vm.envAddress("USDN_PROTOCOL_ADDRESS"));
        } catch {
            _usdnProtocol = IUsdnProtocol(vm.parseAddress(vm.prompt("enter protocol address: ")));
        }

        _wstEthOracleMiddleware = WstEthOracleMiddleware(address(_usdnProtocol.getOracleMiddleware()));
        _liquidationRewardsManager = LiquidationRewardsManager(address(_usdnProtocol.getLiquidationRewardsManager()));
        _rebalancer = Rebalancer(payable(address(_usdnProtocol.getRebalancer())));
    }
}
