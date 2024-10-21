// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "forge-std/Script.sol";
import { Script } from "forge-std/Script.sol";

import { IMultiMinter, MultiMinter } from "../src/utils/sepolia/MultiMinter.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";
import { WstETH as WstETHSepolia } from "../src/utils/sepolia/tokens/WstETH.sol";

contract DeployMultiMint is Script {
    function run() external returns (MultiMinter newMultiMint) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        require(block.chainid == 11_155_111, "DeployMultiMint: allowed only on the test environment");

        SdexSepolia sdex = SdexSepolia(vm.envOr("SDEX_SEPOLIA", address(0)));
        WstETHSepolia wstEth = WstETHSepolia(payable(vm.envOr("WSTETH_SEPOLIA", address(0))));

        bool newSdex = address(sdex) == address(0);
        bool newWstEth = address(wstEth) == address(0);

        vm.startBroadcast(deployerAddress);

        if (newWstEth) {
            wstEth = new WstETHSepolia();
        }
        if (newSdex) {
            sdex = new SdexSepolia();
        }

        newMultiMint = new MultiMinter(address(sdex), address(wstEth));

        if (newSdex) {
            sdex.transferOwnership(address(newMultiMint));
            newMultiMint.acceptOwnershipOf(address(sdex));
        }
        if (newWstEth) {
            wstEth.transferOwnership(address(newMultiMint));
            newMultiMint.acceptOwnershipOf(address(wstEth));
        }
        vm.stopBroadcast();

        address lastMultiMintOwnerAddress = vm.envOr("LAST_MULTIMINT_OWNER_SEPOLIA", address(0));
        if (lastMultiMintOwnerAddress != address(0)) {
            IMultiMinter lastMultiMint = IMultiMinter(vm.envAddress("LAST_MULTIMINT_SEPOLIA"));
            if (!newSdex) {
                vm.prank(lastMultiMintOwnerAddress);
                lastMultiMint.transferOwnershipOf(address(sdex), address(newMultiMint));
                vm.prank(deployerAddress);
                // This call will succeed only if the contract is ownable2step
                try newMultiMint.acceptOwnershipOf(address(sdex)) { } catch { }
            }
            if (!newWstEth) {
                vm.prank(lastMultiMintOwnerAddress);
                IMultiMinter(lastMultiMint).transferOwnershipOf(address(wstEth), address(newMultiMint));
                vm.prank(deployerAddress);
                // This call will succeed only if the contract is ownable2step
                try newMultiMint.acceptOwnershipOf(address(wstEth)) { } catch { }
            }
        }

        require(wstEth.owner() == address(newMultiMint), "DeployMultiMint: WstETH owner is not MultiMinter");
        require(sdex.owner() == address(newMultiMint), "DeployMultiMint: Sdex owner is not MultiMinter");
        require(newMultiMint.owner() == deployerAddress, "DeployMultiMint: MultiMinter owner is not the deployer");
        console.log("WstETHSepolia address", address(wstEth));
        console.log("SdexSepolia address", address(sdex));
        console.log("MultiMinter address", address(newMultiMint));
        console.log("owner of MultiMinter", newMultiMint.owner());
    }
}
