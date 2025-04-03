// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

abstract contract PropertiesDescriptions {
    // Global Invariants
    string constant GLOB_01 = "GLOB-01: A positions tick should never be above the _highestPopulatedTick";
    string constant GLOB_02 = "GLOB-02: The current divisor should never equal the MIN_DIVISOR.";
    string constant GLOB_03 = "GLOB-03: FundingPerDay should never equal 0.";
    string constant GLOB_04 = "GLOB-04: Each pending action should have an associated securityDeposit value.";
    string constant GLOB_05 = "GLOB-05: Trading expo should never go to 0.";
    string constant GLOB_06 = "GLOB-06: Position should never have a leverage smaller that 1.";
    string constant GLOB_07 =
        "GLOB-07: The internal total balance the contract deals with should not be bigger than the real balanceOf.";

    // Deposit Invariants
    string constant DEPI_01 = "DEPI-01: Sender's ETH balance decreased by security deposit";
    string constant DEPI_02 = "DEPI-02: Sender's wstETH balance decreased by deposited amount";
    string constant DEPI_03 = "DEPI-03: Sender's SDEX balance decreased";
    string constant DEPI_04 = "DEPI-04: Protocol's ETH balance increased by security deposit";
    string constant DEPI_05 = "DEPI-05: Protocol's wstETH balance increased by deposit minus pending actions";

    // Deposit Validation Invariants
    string constant DEPV_01 = "DEPV-01: Recipient's USDN shares increased after validation";
    string constant DEPV_02 = "DEPV-02: Caller's USDN shares unchanged";
    string constant DEPV_03 = "DEPV-03: Validator's USDN shares unchanged";
    string constant DEPV_04 = "DEPV-07: Validator's ETH balance increased by security deposit after validation";
    string constant DEPV_05 = "DEPV-05: USDN token total supply changed by pending tokens after validation";
    string constant DEPV_06 = "DEPV-06: Caller's wstETH balance unchanged";
    string constant DEPV_07 = "DEPV-07: Protocol's wstETH balance decreased by pending actions after validation";
    string constant DEPV_08 = "DEPV-08: Validator's wstETH balance unchanged";
    string constant DEPV_09 = "DEPV-09: Caller's wstETH balance unchanged";

    // Withdrawal Initiation Invariants
    string constant WITHI_01 = "WITHI-01: Sender's ETH balance decreased by security deposit";
    string constant WITHI_02 = "WITHI-02: Sender's USDN shares decreased by withdrawn amount";
    string constant WITHI_03 =
        "WITHI-03: Protocol's ETH balance increased by security deposit minus last action's deposit";
    string constant WITHI_04 = "WITHI-04: Protocol's USDN shares increased by withdrawn amount plus pending actions";

    // Withdrawal Validation Invariants
    string constant WITHV_01 = "WITHV-01: Sender's ETH balance increased by action's security deposit value";
    string constant WITHV_02 = "WITHV-02: If successful, sender's wstETH balance increased or remained the same";
    string constant WITHV_03 =
        "WITHV-03: If successful, protocol's ETH balance decreased by action's security deposit value";
    string constant WITHV_04 = "WITHV-04: If successful, protocol's USDN shares decreased";
    string constant WITHV_05 =
        "WITHV-05: If successful, protocol's wstETH balance decreased by at least pending actions";

    // Position Open Initiation Invariants
    string constant POSOPNI_01 = "POSOPNI-01: Protocol's ETH balance increased by security deposit minus last action";
    string constant POSOPNI_02 = "POSOPNI-02: Sender's ETH balance decreased by security deposit minus last action";
    string constant POSOPNI_03 =
        "POSOPNI-03: Protocol's wstETH balance increased by deposit amount minus pending actions";
    string constant POSOPNI_04 = "POSOPNI-04: Sender's wstETH balance decreased by deposit amount";
    string constant POSOPNI_05 = "POSOPNI-05: Position opening without fee must not alter unadjustedPrice(price)";

    // Position Close Initiation Invariants
    string constant POSCLOSI_01 = "POSCLOSI-01: If successful, sender's ETH balance decreased by security deposit";
    string constant POSCLOSI_02 =
        "POSCLOSI-02: If successful, validator's pending action is set to ValidateClosePosition";
    string constant POSCLOSI_03 = "POSCLOSI-03: If successful, protocol's ETH balance increased by security deposit";
    string constant POSCLOSI_04 = "POSCLOSI-04: Sender's wstETH balance unchanged";
    string constant POSCLOSI_05 = "POSCLOSI-05: Protocol's wstETH balance unchanged";
    string constant POSCLOSI_06 = "POSCLOSI-06: If liquidated, sender's ETH balance decreased by pyth price only";
    string constant POSCLOSI_07 = "POSCLOSI-07: If liquidated and initiated, protocol's ETH balance unchanged";
    string constant POSCLOSI_08 =
        "POSCLOSI-08: If liquidated and user is liquidator, their wstETH balance increased by rewards";
    string constant POSCLOSI_09 =
        "POSCLOSI-09: If liquidated and fees collected, protocol's wstETH balance decreased by fees and rewards";
    string constant POSCLOSI_10 = "POSCLOSI-10: If position was liquidated meanwhile, no pending action";

    // Position Open Validation Invariants
    string constant POSOPNV_01 = "POSOPNV-01: If successful, validator's ETH balance increased by security deposits";
    string constant POSOPNV_02 = "POSOPNV-02: If successful, protocol's ETH balance decreased by security deposits";
    string constant POSOPNV_03 = "POSOPNV-03: Protocol's wstETH balance decreased by pending actions";
    string constant POSOPNV_04 = "POSOPNV-04: Sender's wstETH balance unchanged";
    string constant POSOPNV_05 =
        "POSOPNV-05: If liquidated, liquidator's wstETH balance increased by liquidation rewards";
    string constant POSOPNV_06 =
        "POSOPNV-06: If liquidated and validator is liquidator, protocol's wstETH balance decreased by pending actions, liquidation rewards and position profit";

    // Position Close Validation Invariants
    string constant POSCLOSV_01 = "POSCLOSV-01: If successful, sender's ETH balance increased by security deposit";
    string constant POSCLOSV_02 = "POSCLOSV-02: If successful, protocol's ETH balance decreased by security deposit";
    string constant POSCLOSV_03 =
        "POSCLOSV-03: If successful, protocol's wstETH balance decreased by more than pending actions";
    string constant POSCLOSV_04 =
        "POSCLOSV-04: If successful, protocol's wstETH balance decreased by less than close amount + pending actions";
    string constant POSCLOSV_05 =
        "POSCLOSV-05: If successful, recipient's wstETH balance increased by less than close amount";
    string constant POSCLOSV_06 = "POSCLOSV-06: If successful, recipient's wstETH balance increased";
    string constant POSCLOSV_07 =
        "POSCLOSV-07: If successful and sender != validator, validator's ETH balance unchanged";
    string constant POSCLOSV_08 =
        "POSCLOSV-08: If successful and sender != recipient, sender's wstETH balance unchanged";
    string constant POSCLOSV_09 =
        "POSCLOSV-09: If successful and recipient != validator, recipient's ETH balance unchanged";
    string constant POSCLOSV_10 =
        "POSCLOSV-10: If successful and recipient != validator, validator's wstETH balance unchanged";
    string constant POSCLOSV_11 =
        "POSCLOSV-11: If liquidated and validator is liquidator, protocol wstETH decreased by rewards";
    string constant POSCLOSV_12 = "POSCLOSV-12: If liquidated, user wstETH balance changes include liquidation rewards";
    string constant POSCLOSV_13 = "POSCLOSV-13: If liquidated, user wstETH balance unchanged";

    // Pending Actions Validation Invariants
    string constant PENDACTV_01 = "PENDACTV-01: Correct number of actions validated";
    string constant PENDACTV_02 = "PENDACTV-02: Sender's ETH balance increased by security deposit";
    string constant PENDACTV_03 = "PENDACTV-03: Protocol's ETH balance decreased by security deposit";

    // DOS Invariants
    string constant ERR_01 = "ERR_01: Non-whitelisted error should never appear in a call";
}
