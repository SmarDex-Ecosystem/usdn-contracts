// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { MockStETH } from "../src/utils/MockStETH.sol";
import { MockWstETH } from "../src/utils/MockWstETH.sol";
import { MultiMinter } from "../src/utils/sepolia/MultiMinter.sol";
import { Sdex as SdexSepolia } from "../src/utils/sepolia/tokens/Sdex.sol";

contract DeployMultiMint is Script {
    function run() external returns (MultiMinter newMultiMint) {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        require(block.chainid == 11_155_111, "DeployMultiMint: allowed only on the test environment");

        SdexSepolia sdex = SdexSepolia(vm.envAddress("SDEX_SEPOLIA"));
        MockWstETH wstEth = MockWstETH(payable(vm.envAddress("WSTETH_SEPOLIA")));
        MockStETH stEth = MockStETH(payable(vm.envAddress("STETH_SEPOLIA")));

        vm.startBroadcast(deployerAddress);

        newMultiMint = new MultiMinter(address(sdex), address(stEth), address(wstEth));

        sdex.transferOwnership(address(newMultiMint));
        newMultiMint.acceptOwnershipOf(address(sdex));
        stEth.transferOwnership(address(newMultiMint));
        newMultiMint.acceptOwnershipOf(address(stEth));
        wstEth.transferOwnership(address(newMultiMint));
        newMultiMint.acceptOwnershipOf(address(wstEth));

        vm.stopBroadcast();

        require(sdex.owner() == address(newMultiMint), "DeployMultiMint: Sdex owner is not MultiMinter");
        require(stEth.owner() == address(newMultiMint), "DeployMultiMint: StETH owner is not MultiMinter");
        require(wstEth.owner() == address(newMultiMint), "DeployMultiMint: WstETH owner is not MultiMinter");
        require(newMultiMint.owner() == deployerAddress, "DeployMultiMint: MultiMinter owner is not the deployer");
    }
}
