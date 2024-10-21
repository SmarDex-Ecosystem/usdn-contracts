// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "forge-std/Script.sol";
import { Script } from "forge-std/Script.sol";

import { IMultiMinter, IOwnable, MultiMinter } from "../src/utils/sepolia/MultiMinter.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";

contract DeployMultiMint is Script {
    address constant SDEX_SEPOLIA = 0xad65D93735816011CE25674A988E61b74C178D0F;
    address constant MULTIMINT_SEPOLIA = 0x96dd368a9894D1533Edd329032E39eE07d09321c;

    function run() external returns (MultiMinter MultiMinter_) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        address lastMultiMintOwnerAddress = vm.envAddress("LAST_MULTIMINT_OWNER_ADDRESS");
        uint64 nonceDeployer = vm.getNonce(deployerAddress);
        uint64 nonce = vm.getNonce(lastMultiMintOwnerAddress);

        require(block.chainid == 11_155_111, "DeployMultiMint: allowed only on the test environment");
        require(nonceDeployer == 0, "nonceDeployer must be 0");
        require(nonce == 0, "nonce must be 0");

        vm.broadcast(deployerAddress);

        WstETHSepolia wstEth_ = new WstETHSepolia();
        MultiMinter_ = new MultiMinter(SDEX_SEPOLIA, address(wstEth_));
        wstEth_.transferOwnership(address(MultiMinter_));

        vm.stopBroadcast();

        vm.broadcast(lastMultiMintOwnerAddress);
        IMultiMinter(MULTIMINT_SEPOLIA).transferOwnershipOf(IOwnable(SDEX_SEPOLIA), address(MultiMinter_));
        vm.stopBroadcast();

        console.log("WstETHSepolia address", address(wstEth_));
        console.log("SdexSepolia address", SDEX_SEPOLIA);
        console.log("MultiMinter address", address(MultiMinter_));
    }
}
