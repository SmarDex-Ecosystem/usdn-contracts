// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The _prepareInitiateDepositData internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolPrepareInitiateDepositData is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check _prepareInitiateDepositData function revert when the vault balance is empty
     * @custom:given An empty vault balance. This case is not supposed to happen so we need to force it by setting the
     * balance to 0
     * @custom:when The function is called
     * @custom:then The function reverts with the UsdnProtocolEmptyVault error
     */
    function test_emptyBalanceVault() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 100 ether,
                desiredLiqPrice: params.initialPrice * 9 / 10,
                price: params.initialPrice
            })
        );

        bytes32 storageMainSlot =
            keccak256(abi.encode(uint256(keccak256("UsdnProtocol.storage.main")) - 1)) & ~bytes32(uint256(0xff));
        // _balanceVault is the 30th slot in the storage struct
        bytes32 storageSlot = storageMainSlot | bytes32(uint256(31));
        vm.store(address(protocol), storageSlot, 0);

        vm.expectPartialRevert(UsdnProtocolEmptyVault.selector);
        protocol.i_prepareInitiateDepositData(address(this), 1, DISABLE_SHARES_OUT_MIN, abi.encode(params.initialPrice));
    }
}
