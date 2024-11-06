// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract TransferProtocolOwnership is Script {
    /**
     * @notice Transfer protocol ownership to a new owner
     * @dev The script should be run by the current owner, `NEW_OWNER_ADDRESS` and `USDN_PROTOCOL_ADDRESS` should be set
     * in the environment
     * @dev The script will transfer the default admin role to the new owner
     * @dev To run the script in standalone use : `forge script script/03_TransferProtocolOwnership.s.sol -f
     * YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY --broadcast`
     */
    function run() external {
        address newOwner = vm.envAddress("NEW_OWNER_ADDRESS");
        IUsdnProtocol protocol = IUsdnProtocol(vm.envAddress("USDN_PROTOCOL_ADDRESS"));
        address defaultAdmin = protocol.defaultAdmin();

        vm.startBroadcast(defaultAdmin);

        protocol.beginDefaultAdminTransfer(newOwner);

        vm.stopBroadcast();
    }
}
