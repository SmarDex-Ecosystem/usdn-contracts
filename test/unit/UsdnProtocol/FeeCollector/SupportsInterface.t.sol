// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IFeeCollectorCallback } from "../../../../src/interfaces/UsdnProtocol/IFeeCollectorCallback.sol";

/**
 * @custom:feature The {supportsInterface} function of the `FeeCollector` contract
 * @custom:background Given a `FeeCollector` contract
 */
contract TestFeeCollectorSupportsInterface is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check that the `FeeCollector` contract supports the correct interfaces
     * @custom:given A deployed `FeeCollector` contract
     * @custom:when The {supportsInterface} function is called with the interface IDs
     * @custom:then The function should return `true` for the supported interfaces and `false` for any other
     * interface
     */
    function test_supportsInterfaceFeeCollector() public view {
        assertEq(feeCollector.supportsInterface(type(IERC165).interfaceId), true, "IERC165_ID supported");
        assertEq(
            feeCollector.supportsInterface(type(IFeeCollectorCallback).interfaceId),
            true,
            "IFeeCollectorCallback_ID supported"
        );
        assertEq(feeCollector.supportsInterface(""), false, "unknown interface ID");
    }
}
