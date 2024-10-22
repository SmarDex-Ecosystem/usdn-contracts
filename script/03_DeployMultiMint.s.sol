// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "forge-std/Script.sol";
import { Script } from "forge-std/Script.sol";

import { MockStETH } from "../src/utils/MockStETH.sol";
import { MockWstETH } from "../src/utils/MockWstETH.sol";
import { IMultiMinter, MultiMinter } from "../src/utils/sepolia/MultiMinter.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";

contract DeployMultiMint is Script {
    function run() external returns (MultiMinter newMultiMint) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        require(block.chainid == 11_155_111, "DeployMultiMint: allowed only on the test environment");

        SdexSepolia sdex = SdexSepolia(vm.envOr("SDEX_SEPOLIA", address(0)));
        MockWstETH wstEth = MockWstETH(payable(vm.envOr("WSTETH_SEPOLIA", address(0))));
        MockStETH stEth = MockStETH(payable(vm.envOr("STETH_SEPOLIA", address(0))));

        bool newSdex = address(sdex) == address(0);
        bool newWstEth = address(wstEth) == address(0) || address(stEth) == address(0);

        vm.startBroadcast(deployerAddress);

        if (newWstEth) {
            stEth = new MockStETH();
            wstEth = new MockWstETH(stEth);
        }
        if (newSdex) {
            sdex = new SdexSepolia();
        }

        newMultiMint = new MultiMinter(address(sdex), address(stEth), address(wstEth));

        if (newSdex) {
            sdex.transferOwnership(address(newMultiMint));
            newMultiMint.acceptOwnershipOf(address(sdex));
        }
        if (newWstEth) {
            stEth.transferOwnership(address(newMultiMint));
            newMultiMint.acceptOwnershipOf(address(stEth));
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
                lastMultiMint.transferOwnershipOf(address(wstEth), address(newMultiMint));
                vm.prank(deployerAddress);
                // This call will succeed only if the contract is ownable2step
                try newMultiMint.acceptOwnershipOf(address(wstEth)) { } catch { }
                vm.prank(lastMultiMintOwnerAddress);
                lastMultiMint.transferOwnershipOf(address(stEth), address(newMultiMint));
                vm.prank(deployerAddress);
                // This call will succeed only if the contract is ownable2step
                try newMultiMint.acceptOwnershipOf(address(stEth)) { } catch { }
            }
        }

        require(sdex.owner() == address(newMultiMint), "DeployMultiMint: Sdex owner is not MultiMinter");
        require(stEth.owner() == address(newMultiMint), "DeployMultiMint: StETH owner is not MultiMinter");
        require(wstEth.owner() == address(newMultiMint), "DeployMultiMint: WstETH owner is not MultiMinter");
        require(newMultiMint.owner() == deployerAddress, "DeployMultiMint: MultiMinter owner is not the deployer");
        console.log("SdexSepolia address", address(sdex));
        console.log("StETHSepolia address", address(stEth));
        console.log("WstETHSepolia address", address(wstEth));
        console.log("MultiMinter address", address(newMultiMint));
        console.log("owner of MultiMinter", newMultiMint.owner());
    }
}
