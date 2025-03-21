// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "./util/FunctionCalls.sol";

import "forge-std/StdStyle.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract FuzzSetup is FunctionCalls {
    using SignedMath for int256;

    function setup(address deployerContract) internal {
        DEPLOYER = deployerContract;

        deployPeriphery(DEPLOYER);
        deployPyth();
        deployChainlink();
        deployOracleMiddleware(address(wstETH));
        deployLiquidationRewardsManager(address(wstETH));
        deployProtocol();
        deployRebalancer();
        mintTokens();
        handlePostDeployment();
        initializeUsdnProtocol(INIT_DEPOSIT_AMOUNT, INIT_LONG_AMOUNT);
    }

    function deployPeriphery(address admin) internal {
        usdn = new Usdn();
        wusdn = new Wusdn(usdn);
        wstETH = new WstETH();
        sdex = new Sdex();
    }

    function deployPyth() internal {
        pyth = new MockPyth();
    }

    function deployChainlink() internal {
        chainlink = new MockChainlinkOnChain();
    }

    function deployOracleMiddleware(address wstETHAddress) internal {
        wstEthOracleMiddleware = new MockWstEthOracleMiddleware(
            address(pyth), PYTH_FEED_ID, address(chainlink), wstETHAddress, CHAINLINK_PRICE_VALIDITY
        );

        setPrice(2111);
    }

    function deployLiquidationRewardsManager(address wstETHAddress) internal {
        liquidationRewardsManager = new LiquidationRewardsManager(IWstETH(wstETHAddress));
    }

    function deployProtocol() internal {
        feeCollector = new FeeCollector(); //NOTE: added fuzzing contract into collector's constructor
        usdnProtocolFallback = new UsdnProtocolFallback();
        usdnProtocolHandler = new UsdnProtocolHandler();

        // @TODO change to new implemntation
        bytes memory initData = abi.encodeCall(
            usdnProtocolHandler.initializeStorageFuzz,
            (
                usdn,
                sdex,
                wstETH,
                wstEthOracleMiddleware,
                liquidationRewardsManager,
                100, // tick spacing 100 = 1.05%
                address(feeCollector),
                usdnProtocolFallback
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(usdnProtocolHandler), initData);

        usdnProtocol = IUsdnProtocolHandler(address(proxy));

        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, address(this));
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, address(this));

        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, address(this));
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, address(this));
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, address(this));
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, address(this));
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, address(this));
    }

    function deployRebalancer() internal {
        rebalancer = new RebalancerHandler(usdnProtocol);
    }

    function handlePostDeployment() internal {
        usdnProtocol.setRebalancer(rebalancer);
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.renounceRole(usdn.DEFAULT_ADMIN_ROLE(), DEPLOYER);
    }

    function initializeUsdnProtocol(uint256 depositAmount, uint256 longAmount) public {
        setPrice(2222);

        usdnProtocol.setExpoImbalanceLimits(0, 200, 0, 0, 0, 0); // 2% for deposit

        usdnProtocol.setMinLongPosition(2 ether);

        uint128 minInitAmount = uint128(usdnProtocol.getMinLongPosition() * 2);
        uint128 initialDeposit = uint128(
            (10_000 * minInitAmount) //BPS_DIVISOR
                / uint256(usdnProtocol.getDepositExpoImbalanceLimitBps())
        );
        uint128 initialLong = initialDeposit;
        uint128 INITIAL_PRICE = 3000 ether;

        int24 tick = usdnProtocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        uint128 price = usdnProtocol.getEffectivePriceForTick(tick);

        wstETH.approve(address(usdnProtocol), initialDeposit + initialLong);

        // vm.deal(USER1, 1000e18);
        // vm.prank(USER1);
        usdnProtocol.initialize{ value: 1 }(initialDeposit, initialLong, price, "");

        int24 highestTIck = usdnProtocol.getHighestPopulatedTick();
        initialLongPositionPrice = usdnProtocol.getEffectivePriceForTick(highestTIck);
        usdnProtocol.setExpoImbalanceLimits(
            uint256(500), uint256(500), uint256(600), uint256(600), uint256(350), int256(400)
        );
    }

    function mintTokens() internal {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(usdnProtocol), type(uint256).max);
        for (uint8 i = 0; i < USERS.length; i++) {
            address user = USERS[i];
            vm.prank(user);
            wstETH.mintAndApprove(user, 10_000 ether, address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            sdex.mintAndApprove(user, 10_000 ether, address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            usdn.approve(address(usdnProtocol), type(uint256).max);
            vm.prank(user);
            wstETH.approve(address(0xdead), type(uint256).max);
            vm.prank(user);
            wstETH.approve(address(rebalancer), type(uint256).max);
            vm.prank(user);
            sdex.approve(address(0xdead), type(uint256).max);
            vm.deal(user, 30_000 ether);
        }
    }

    function setPrice(int256 priceUSD) internal {
        setInitialChainlinkPrice(priceUSD);
        setInitialPythPrice();
    }

    function setInitialChainlinkPrice(int256 priceUSD) internal {
        chainlink.setLastPrice(priceUSD * 1e8);
        chainlink.setLastPublishTime(block.timestamp);

        uint80 roundId = 1;
        int256 answer = priceUSD * 1e8; //2k
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 1;

        chainlink.setLatestRoundData(roundId, answer, startedAt, answeredInRound);
    }

    function setInitialPythPrice() internal {
        (, int256 ethPrice,,,) = chainlink.latestRoundData();
        pyth.setLastPublishTime(block.timestamp + wstEthOracleMiddleware.getValidationDelay());
        pyth.setPrice(int64(ethPrice));
    }

    fallback() external payable { }
    receive() external payable { }
}
