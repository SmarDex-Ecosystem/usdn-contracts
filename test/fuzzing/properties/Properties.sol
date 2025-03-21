// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Properties_DEPI.sol";
import "./Properties_DEPV.sol";

import "./Properties_ERR.sol";
import "./Properties_GLOB.sol";
import "./Properties_LIQ.sol";
import "./Properties_PENDACTV.sol";
import "./Properties_POSCLOSI.sol";
import "./Properties_POSCLOSV.sol";
import "./Properties_POSOPNI.sol";
import "./Properties_POSOPNV.sol";
import "./Properties_WITHI.sol";
import "./Properties_WITHV.sol";

abstract contract Properties is
    Properties_DEPI,
    Properties_DEPV,
    Properties_WITHI,
    Properties_WITHV,
    Properties_POSOPNI,
    Properties_POSOPNV,
    Properties_POSCLOSI,
    Properties_POSCLOSV,
    Properties_PENDACTV,
    Properties_GLOB,
    Properties_LIQ,
    Properties_ERR
{ }
