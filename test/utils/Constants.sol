// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/* -------------------------------------------------------------------------- */
/*                              General Constants                             */
/* -------------------------------------------------------------------------- */

/* -------------------------------- Accounts -------------------------------- */
// contract deployer
address payable constant DEPLOYER = payable(address(0x1234123412341234123412341234123412341234));

// proxies contract admin
address payable constant ADMIN = payable(address(0x1212121212121212121212121212121212121212));

// roles
address payable constant SET_EXTERNAL_MANAGER = payable(address(0x1313131313131313131313131313131313131313));
address payable constant CRITICAL_FUNCTIONS_MANAGER = payable(address(0x1414141414141414141414141414141414141414));
address payable constant SET_PROTOCOL_PARAMS_MANAGER = payable(address(0x1515151515151515151515151515151515151515));
address payable constant SET_USDN_PARAMS_MANAGER = payable(address(0x1616161616161616161616161616161616161616));
address payable constant SET_OPTIONS_MANAGER = payable(address(0x1717171717171717171717171717171717171717));
address payable constant PROXY_UPGRADE_MANAGER = payable(address(0x1717171717171717171717171717171717171718));
address payable constant PAUSER_MANAGER = payable(address(0x1717171717171717171717171717171717171719));
address payable constant UNPAUSER_MANAGER = payable(address(0x1717171717171717171717171717171717171720));
address payable constant SET_EXTERNAL_ROLE_ADMIN = payable(address(0x1818181818181818181818181818181818181818));
address payable constant CRITICAL_FUNCTIONS_ROLE_ADMIN = payable(address(0x1919191919191919191919191919191919191919));
address payable constant SET_PROTOCOL_PARAMS_ROLE_ADMIN = payable(address(0x2020202020202020202020202020202020202020));
address payable constant SET_USDN_PARAMS_ROLE_ADMIN = payable(address(0x2121212121212121212121212121212121212121));
address payable constant SET_OPTIONS_ROLE_ADMIN = payable(address(0x2323232323232323232323232323232323232323));
address payable constant PROXY_UPGRADE_ROLE_ADMIN = payable(address(0x2424242424242424242424242424242424242424));

// generic users
address payable constant USER_1 = payable(address(0x1111111111111111111111111111111111111111));
address payable constant USER_2 = payable(address(0x2222222222222222222222222222222222222222));
address payable constant USER_3 = payable(address(0x3333333333333333333333333333333333333333));
address payable constant USER_4 = payable(address(0x4444444444444444444444444444444444444444));

/* -------------------------------------------------------------------------- */
/*                              Ethereum mainnet                              */
/* -------------------------------------------------------------------------- */

/* --------------------------------- ERC-20 --------------------------------- */

address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
address constant USDT = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant SDEX = address(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);
address constant WSTETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

/* --------------------------------- Oracles -------------------------------- */

address constant PYTH_ORACLE = address(0x4305FB66699C3B2702D4d05CF36551390A4c69C6);
address constant CHAINLINK_ORACLE_ETH = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH-USD
bytes32 constant PYTH_ETH_USD = bytes32(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace);
bytes32 constant PYTH_WSTETH_USD = bytes32(0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784);
bytes32 constant REDSTONE_ETH_USD = bytes32("ETH");

/* -------------------------------------------------------------------------- */
/*                               Polygon mainnet                              */
/* -------------------------------------------------------------------------- */

/* --------------------------------- ERC-20 --------------------------------- */

address constant POLYGON_WMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
address constant POLYGON_USDC = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
address constant POLYGON_USDT = address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
address constant POLYGON_WETH = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
address constant POLYGON_SDEX = address(0x6899fAcE15c14348E1759371049ab64A3a06bFA6);

/* -------------------------------------------------------------------------- */
/*                              BNB Chain mainnet                             */
/* -------------------------------------------------------------------------- */

/* --------------------------------- ERC-20 --------------------------------- */

address constant BSC_WBNB = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
address constant BSC_USDC = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
address constant BSC_USDT = address(0x0a70dDf7cDBa3E8b6277C9DDcAf2185e8B6f539f);
address constant BSC_WETH = address(0x4DB5a66E937A9F4473fA95b1cAF1d1E1D62E29EA);
address constant BSC_SDEX = address(0xFdc66A08B0d0Dc44c17bbd471B88f49F50CdD20F);

/* -------------------------------------------------------------------------- */
/*                              Arbitrum mainnet                              */
/* -------------------------------------------------------------------------- */

/* --------------------------------- ERC-20 --------------------------------- */

address constant ARBITRUM_USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
address constant ARBITRUM_USDT = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
address constant ARBITRUM_WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
address constant ARBITRUM_SDEX = address(0xabD587f2607542723b17f14d00d99b987C29b074);

/* -------------------------------------------------------------------------- */
/*                                Base mainnet                                */
/* -------------------------------------------------------------------------- */

/* --------------------------------- ERC-20 --------------------------------- */

address constant BASE_USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
address constant BASE_USDBC = address(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);
address constant BASE_WETH = address(0x4200000000000000000000000000000000000006);
address constant BASE_SDEX = address(0xFd4330b0312fdEEC6d4225075b82E00493FF2e3f);
