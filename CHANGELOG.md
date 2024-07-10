# Changelog

## [0.16.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.15.0...v0.16.0) (2024-06-21)


### ⚠ BREAKING CHANGES

* **rebalancer:** withdrawal in two steps ([#361](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/361))
* **rebalancer:** `depositAssets` becomes `initiateDepositAssets` and must be followed by `validateDepositAssets` after a mandatory delay, rebalancer events have changed
* Usage of Ownable2Step instead of Ownable ([#329](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/329))
* remove router ([#340](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/340))
* rename package ([#335](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/335))
* **actions:** a new parameter `permit2TokenBitfield` of type `Permit2TokenBitfield.Bitfield` (an alias for `uint8`) was added to `initiateDeposit` and `initiateOpenPosition` to indicate whether permit2 should be used for the asset token and sdex.
* **middleware:** the constructor for the oracle middleware takes an additional parameter for the redstone feed ID, `IOracleMiddleware.setRecentPriceDelay` renamed to become `IOracleMiddleware.setPythRecentPriceDelay`, `IPythOracle.getRecentPriceDelay` renamed to become `IPythOracle.getPythRecentPriceDelay`, `IOracleMiddlewareEvents.RecentPriceDelayUpdated` renamed to become `IOracleMiddlewareEvents.PythRecentPriceDelayUpdated`

### Features

* **actions:** add native support for permit2 transfers ([#318](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/318)) ([ff4d88a](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ff4d88a754f25eba44966e0d5fe8a95314bdc9b6))
* change in external ([#326](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/326)) ([d606d6c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d606d6cd618a1d6db98f7aec6e1b7b06dcf08e99))
* **limits:** changed initial limits for opening position and depositing in vault ([#311](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/311)) ([89bb976](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/89bb976ff8afacd4e3541650516803eddf2ff634))
* **liquidation-rewards-manager:** add the setting for the rebalancer trigger's gas used ([#356](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/356)) ([e1b720b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/e1b720bb4ff2f11c43a55c6614aa8a5b694b09b2))
* **middleware:** add sanity check on Pyth price timestamp ([#365](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/365)) ([da5c5dc](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/da5c5dcbde5c2d05f02a0a43ba62e5b40d12de08))
* **middleware:** add support for redstone oracle ([#304](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/304)) ([7b851e0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7b851e033db11da122e8e9f87d36eda75415ef9c))
* new initial values ([#316](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/316)) ([c820f45](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c820f457aa9e38237c4135ed8a9e3dd77fcccde1))
* preview deposit ([#339](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/339)) ([c522ef8](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c522ef837d00fff8fa4ba01c0c78ed994b07ec74))
* **rebalancer:** add a case to deal with dust in the position ([#367](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/367)) ([073446e](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/073446e29a801a76fc524730e0654583da9d7c22))
* **rebalancer:** add the rebalancer gas usage to the liquidation rewards calculations ([#372](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/372)) ([045a5e0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/045a5e03ed9868d27854ff47c7829ac42c941b9b))
* **rebalancer:** add the reentrancy guard to the rebalancer's initiateClosePosition function ([#358](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/358)) ([901f72e](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/901f72e7c241d9f2935a75f532dfe20ff248aed2))
* **rebalancer:** add the trigger of the rebalancer when the imbalance is too high ([#289](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/289)) ([1593e34](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/1593e34206a4e156626cf38e050d0f9bd3decd81))
* **rebalancer:** close imbalance limit bps ([#325](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/325)) ([da690f6](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/da690f6f122227a659433db70212558905cee57e))
* **rebalancer:** deposit in two steps ([#353](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/353)) ([846f83d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/846f83dc9d56eabad729752154b697f888e3c593))
* **rebalancer:** handle refunds ([#359](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/359)) ([c07c257](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c07c2577edcf5217d13b483325e0d1770c636c00))
* **rebalancer:** include close bonus ([#360](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/360)) ([2829bdf](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2829bdf459cbd517f090cce44d817969dcb1b830))
* **rebalancer:** no trigger condition on close limit ([#344](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/344)) ([84bec22](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/84bec22b6a7b48b45bf95e3ed29ceffa01177597))
* **rebalancer:** partial close ([#343](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/343)) ([0695099](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/069509975e99f97dddcb2c7dff7de373bb5c0e28))
* **rebalancer:** support eip-165 and IOwnershipCallback ([#313](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/313)) ([885cc11](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/885cc1124c662b00e15cb88ada7d44948686f403))
* **rebalancer:** withdrawal in two steps ([#361](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/361)) ([5609432](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/56094326f6bc97a101ce5099097b483400f4ed80))
* relative imports in test folder ([#336](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/336)) ([a030466](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a03046633f765a5aed8a51133ee2cfe216cea5dd))
* **router:** validate open position ([#306](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/306)) ([df22c84](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/df22c849adc0cc6102df8ee6c110ed7bf1df59a0))
* Usage of Ownable2Step instead of Ownable ([#329](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/329)) ([bdc88e3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/bdc88e37d2a43fc384d8857d2087959a72048b08))
* **usdn:** wusdn tests and wrapShares ([#346](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/346)) ([b561544](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b56154425912fdada3746ae6878be65bbe993a72))


### Bug Fixes

* **actions:** imbalance check on close ([#342](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/342)) ([45f76a3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/45f76a343ef9aa02de72c61c86889e23a6994db3))
* convert all absolute imports to relative ([#363](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/363)) ([7d5f7d1](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7d5f7d131bcd92abff3c5e58029253699b6b193d))
* middleware interface ([#341](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/341)) ([b597e48](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b597e482595bc31ec374e540adfdb37adad9c9d0))
* slither errors ([#321](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/321)) ([80f6793](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/80f67930462348831cbe0ce99c51fb9f8fc94409))
* use `_lastPrice` for USDN rebase ([#347](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/347)) ([2e80cf8](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2e80cf85f06cb96cf581bd0a84d90e64c83c2daa))


### Performance Improvements

* constants in a new lib ([#364](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/364)) ([c97a739](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c97a7396adf4a1a74863d3cc8aa8df18d8a0957b))
* **hugeuint:** use solady implementation for clz ([#327](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/327)) ([3e4c763](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3e4c763e92ed3fc089fa924c6cacb707942b5554))
* refacto PositionData ([#362](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/362)) ([91fd3cc](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/91fd3cc429956d7b511ad430e2859e7180c09bc1))


### Miscellaneous Chores

* rename package ([#335](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/335)) ([6a248fe](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6a248fe17fc8f91bb2d674f352f07396f2267ffe))


### Code Refactoring

* remove router ([#340](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/340)) ([4b95158](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4b95158dc86b57f58f9d4205ffbbb4b85194d749))

## [0.15.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.14.0...v0.15.0) (2024-06-06)


### ⚠ BREAKING CHANGES

* **actions:** `initiateClosePosition` has a new `validator` argument, `validateClosePosition` now expects the validator as first argument, the `InitiatedClosePosition` event has an additional `validator` parameter, the `ValidatedClosePosition` event now reports the validator address instead of the owner.
* **actions:** the `initiateOpenPosition` action now returns a boolean as first argument on top of the position ID
* **middleware:** the `IBaseOracleMiddleware.parseAndValidatePrice` function has an additional `bytes32` parameter for the unique action identifier
* **rewards:** the `getLiquidationRewards` function has an additional parameter for the protocol action enum
* **rebalancer:** `setExpoImbalanceLimits` has a fifth argument called `newLongImbalanceTargetBps`, and the `ImbalanceLimitsUpdated` event has the same fifth argument. Also, the getter `getExpoImbalanceLimits` has been removed and split into 4 functions, one for each imbalance limit.

### Features

* **actions:** add validator argument to `initiateClosePosition` ([#302](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/302)) ([ad88128](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ad881286aeef8eda7dd510f372a57780fb846c1d))
* **actions:** allow rebalancer user position close with full amount ([#270](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/270)) ([4422071](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4422071b8de0c545641b3dd05dc59fb3f0854568))
* **actions:** block actions pending liquidations ([#227](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/227)) ([d10bb22](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d10bb22541b25f8c19cd20d5b5c92340f518d685))
* **actions:** return success status in all external user actions ([#281](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/281)) ([28120c3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/28120c34fd7fb5b01986b77cad9d6f7c5a80f354))
* **actions:** transfer position ownership ([#282](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/282)) ([9a0fee7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/9a0fee77e13372969e4129211346db76f1241dda))
* **admin:** remove blocked pending action ([#293](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/293)) ([c8d354b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c8d354be0303f05f9ce50e886932c67026e6926e))
* default validation deadline ([#286](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/286)) ([186a58b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/186a58bfab1931cbac8389de028f811f3e0cf5cc))
* ETH price feed ([#298](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/298)) ([c4eab34](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c4eab34a782850650380b158ffb7df08c7484c5d))
* **middleware:** chainlink validate ([#292](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/292)) ([8399439](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/839943901df3db75c281fc5edd71909f0d44dd77))
* **oracle:** add penaltyBps ([#291](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/291)) ([ddab421](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ddab4217efec8d711c92f1c80a669a80d0dc6830))
* **rebalancer:** add a variable for the max leverage of the rebalancer ([#267](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/267)) ([6784245](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6784245c2231e575ad0a3096cc30e3ff58f214a8))
* **rebalancer:** add a variable to track which version got liquidated last ([#266](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/266)) ([7f4c984](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7f4c9845d36ae59952f79efcf590f81a83ebe140))
* **rebalancer:** add imbalance target setting ([#263](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/263)) ([296b53b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/296b53bd8e0783db465b65bea7637d7e5f6c733a))
* **rebalancer:** set allowance of the usdn protocol ([#271](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/271)) ([b5b684b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b5b684be64d45a0c3e9c8e35dfe6030e7bbb5ddf))
* **rewards:** add protocol action to the rewards manager input ([#274](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/274)) ([7a14bdf](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7a14bdf585e8f3f592b59f4b6179314ef025ce04))
* **router:** add commands for wsteth and steth ([#277](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/277)) ([995d6b0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/995d6b0c43e651b1280f17bd1b139921dbd4b3b3))
* **router:** add ethAmount in src and tests ([#301](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/301)) ([95d5a02](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/95d5a021e03914930c298b42e5f12d5497f7917c))
* **router:** initiate deposit command ([#278](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/278)) ([02ea2e4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/02ea2e473ed6a21a883b33be906691d7c351a313))
* **router:** initiate open position ([#296](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/296)) ([777cbbf](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/777cbbf473356cfed989bfd9c0478035508874f6))
* **router:** initiate withdrawal ([#285](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/285)) ([d4379ed](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d4379ede721e526c3c7d7a8905daf66d67b65aee))
* **router:** refacto natspec ([#300](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/300)) ([115ba2e](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/115ba2e095185e6d419078922aead25185dabd0f))
* **router:** retrieve success from external call ([#294](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/294)) ([f965832](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f965832fb8ced5de7fd3b91fa381d2f68d5c2bb8))
* **router:** universal router skeleton ([#245](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/245)) ([844b4f7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/844b4f776c0e804f882fff01cbc9a6ed43ec7cf4))
* **router:** validate deposit ([#297](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/297)) ([bb71753](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/bb71753043903cfcdfccff44a005017561e7c759))
* **router:** validate withdraw ([#299](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/299)) ([ba2b8f0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ba2b8f0925117d106abb1b36d3d1692ac03807c3))
* standardize and fix natspec erros ([#303](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/303)) ([8b3f871](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/8b3f871d1e859e1c3ee5c77cb723abadf99b18ec))


### Bug Fixes

* **actions:** disallow closing a position that was not validated ([#295](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/295)) ([ff8f8cb](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ff8f8cbb140653151b5590c508a8b5c3f387983d))
* **actions:** take pending vault actions into account in imbalance checks ([#287](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/287)) ([045c9b7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/045c9b7e063aaff3c0046dae663566e7536b227f))
* **init:** add imbalance checks during initialization ([#290](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/290)) ([5689657](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/5689657dc301662400b35ec79b5dc322f4733d0d))


### Code Refactoring

* **middleware:** add unique action ID to middleware params ([#284](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/284)) ([ceccd7a](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ceccd7abde23bfb33be7a7bc794fe17efe6ccc13))

## [0.14.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.13.0...v0.14.0) (2024-05-17)


### ⚠ BREAKING CHANGES

* **actions:** add to and validator in pending actions ([#242](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/242))
* **rebalancer:** adds the Rebalancer in the USDN protocol, deployment script etc. ([#259](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/259))
* **usdn:** The `LiquidationRewardsManager.getLiquidationRewards` function has an additional argument `rebaseCallbackResult` of type `bytes`.
* **middleware:** `getConfRatio` is now called `getConfRatioBps`. `getMaxConfRatio` has been replaced by `MAX_CONF_RATIO`. `getConfRatioDenom` has been replaced by `BPS_DIVISOR`.
* **order-manager:** everything related to the order manager has been removed

### Features

* **actions:** add to and validator in pending actions ([#242](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/242)) ([5d134a8](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/5d134a8731380e79f6d92e3c65c44dbdd4d9fc40))
* add separate fee parameter for vault actions ([#244](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/244)) ([ccad861](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ccad861bf3448990af1f92536ed9820da86f8b25))
* **order-manager:** adds the order manager and tests ([#249](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/249)) ([1a59ba0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/1a59ba03c617f8c370e8b1ce29b5afc611d31bfb))
* **order-manager:** remove all the components of the order manager as well as the contract itself ([#246](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/246)) ([fcaee82](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/fcaee829976c7a623fb2e88d500fbf34150f72f2))
* **params:** add new parameter for the rebalancer bonus ([#260](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/260)) ([f775065](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f77506506741f98e8c01f6fdf094b6b871212603))
* **rebalancer:** adds the Rebalancer in the USDN protocol, deployment script etc. ([#259](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/259)) ([924f73f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/924f73fde95cca7d2cfbf8c2098a4a614bbd5d10))
* set a minimum deposit for user in the rebalancer ([#265](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/265)) ([f542684](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f5426847edc765871a2055ab9a8d935f3bcb1c6b))
* **usdn:** add rebase callback ([#253](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/253)) ([0f75211](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/0f75211c0536e97ea859bbed6e017a9b5f77e6a0))


### Bug Fixes

* **usdn:** decrease allowance even if token amount is zero ([#248](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/248)) ([030d90f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/030d90ff3b94ffffc51033d3ddc65c7c4f3fad74))


### Code Refactoring

* **middleware:** cleanup + natspec ([#256](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/256)) ([a9b763f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a9b763f0cf299ad1a8dfa3d42f70dc623b63018f))

## [0.13.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.12.1...v0.13.0) (2024-05-03)


### ⚠ BREAKING CHANGES

* **open-pos:** The fourth argument of InitiatedOpenPosition is now the position total expo instead of its leverage
* use `PositionId` wherever possible ([#238](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/238))
* **types:** removed common struct in all pending actions structs ([#237](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/237))
* **initial-close:** A position cannot be partially closed if the remaining amount of collateral is greater than 0 and lower than _minLongPosition
* The `getMinLongPosition` function now returns an amount in `_assets`
* removed getLiquidationMultiplier; function getEffectiveTickForPrice(uint128 price, uint256 liqMultiplier) has been replaced with getEffectiveTickForPrice(uint128 price, uint256 assetPrice, uint256 longTradingExpo, HugeUint.Uint512 memory accumulator, int24 tickSpacing); function getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) has been replaced with getEffectivePriceForTick(int24 tick, uint256 assetPrice, uint256 longTradingExpo, HugeUint.Uint512 memory accumulator); the PendingAction struct now uses a struct PendingActionCommonData for its first field, replacing action, timestamp, user to, securityDepositValue. For consistency, the amount field was renamed to var2, var2 to var3, etc.; the DepositPendingAction, WithdrawalPendingAction and LongPendingAction now use the new PendingActionCommonData struct as first field; for LongPendingAction, the field closeTotalExpo was renamed to closePosTotalExpo and is used for a different purpose.; the field closeTempTransfer was renamed to closeBoundedPositionValue.
* **oracle-middleware:** error OracleMiddlewareInsufficientFee has been renamed OracleMiddlewareIncorrectFee
* change the name of the function getMaxInitializedTick to getHighestPopulatedTick
* add to parameter in main functions ([#109](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/109))
* **initiate-close:** The event now contins the original value on the position and the amount to be subtracted from it

### Features

* **actions:** event when the security deposit is refunded ([#222](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/222)) ([be37f6f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/be37f6f94e12ab59762af8446e8002b86295c10e))
* add _calcTickWithoutPenalty ([#241](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/241)) ([77d4f86](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/77d4f864b735afcaa3268a8e7a2c7c34b3921696))
* add `previewWithdraw` function ([#218](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/218)) ([237a474](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/237a47488938fbe03257f2a6f87e8712a28f18e7))
* add to parameter in main functions ([#109](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/109)) ([257092f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/257092fdf11f4aa8062c98b7c74b85dd2fcd2a9f))
* change minLongPosition to represent the amount of collateral ([#229](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/229)) ([08f63dc](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/08f63dcf050c40f31e4b4f1338bb0d9db35e31a6))
* **initial-close:** revert if the remaining position not greater or equal to _minLongPosition ([#236](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/236)) ([6e0c256](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6e0c256815dee718b6e251db5f4f174494e83848))
* **open-pos:** replace the leverage by the position total expo in the open position events ([#239](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/239)) ([9b4f5a4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/9b4f5a437f2e54c0fb4ac6479bd8a91e5a7e8473))
* **oracle-middleware:** make the oracle middleware revert if the validation cost is not exact ([#217](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/217)) ([e92be5d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/e92be5d433ab2d17ba728daea6e15d860c6a2e5a))
* reward user actions when a position is liquidated ([#205](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/205)) ([76091ee](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/76091ee27c602bbac10d7ebf4c24f61ce24b2524))
* **rewards:** add priceData to the parameters sent to the liquidation rewards manager ([#233](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/233)) ([1b1cc88](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/1b1cc88318d79242d4753fb5cc35021539eb59fa))
* **rewards:** apply the multiplicator only on the tick liquidation cost ([#231](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/231)) ([5eaebbd](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/5eaebbd6c1635713547fb708ecd401ab97452da7))


### Bug Fixes

* **init-open:** remove a residue of the min position value check ([#243](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/243)) ([3f9e405](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3f9e405da6f475995b606767bea1c1fa5cac3d12))
* outdated pyth data ([#221](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/221)) ([bf249b3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/bf249b3b1cc3dbaf471d1ced378215cbe390d6c2))


### Code Refactoring

* **initiate-close:** change the values sent in the InitiatedClosePosition event ([#210](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/210)) ([cf67c66](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/cf67c66bb1f173da1b70f6fe0d00bf6cabf27cfd))
* replace liquidation multiplier with accumulator ([#206](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/206)) ([d60a3a9](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d60a3a94bb327fe527e2eed6f92f7ac8960ed57f))
* test and rename `_maxInitializedTick` into `_highestPopulatedTick` ([#203](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/203)) ([a418d5c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a418d5c4a642fd7b484b32923c5fe118e21e0b44))
* **types:** removed common struct in all pending actions structs ([#237](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/237)) ([78b2175](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/78b21757e22404d4f0255399f49f5eb0cd04d50e))
* use `PositionId` wherever possible ([#238](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/238)) ([d0f7ee1](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d0f7ee19b66e64282df119b0c5fda432a2c1167d))

## [0.12.1](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.12.0...v0.12.1) (2024-04-18)


### Features

* **deposit:** minimum deposit amount ([#177](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/177)) ([5679c96](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/5679c965f85c0c6ee3ae1a0c34154a2fa8ad07b3))
* library for uint512 math ([#193](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/193)) ([b6dd164](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b6dd1648d1f161550fe4c17b90abbcb6a7adcbde))
* **order-manager:** add a contract to manage orders in tick ([#170](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/170)) ([90d756a](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/90d756a7eaf31adc383373d0e961420c50a3e52c))
* **order-manager:** add the order manager to the USDN protocol and the deployment script ([#188](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/188)) ([ed0d4d6](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ed0d4d6e0946ea65021470ca0e023d62207207f6))


### Bug Fixes

* **core:** edge case of PnL calculation with negative trading expo ([#181](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/181)) ([132cb9d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/132cb9d6b778c951d2a32b70b49ca155bbe4677f))
* **limits:** limits-denominator ([3ea4a14](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3ea4a146e84e5f21fe5e0c9e956ae7a8a1742ee9))

## [0.12.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.11.1...v0.12.0) (2024-04-04)


### ⚠ BREAKING CHANGES

* **withdraw:** `initiateWithdrawal` now takes an input amount of USDN shares instead of USDN tokens, and the type is `uint152`. The `VaultPendingAction` type has been replaced by `DepositPendingAction` and `WithdrawalPendingAction`, the `PendingAction` and `LongPendingAction` types have re-ordered fields.
* **sdex-burn:** A user calling `initiateDeposit` now needs to have enough SDEX tokens and to have approved the spending of his tokens by the USDN protocol. `getUsdnDecimals` has been removed, use `TOKENS_DECIMALS` instead, or the `decimals()` function on the token contract instead.
* **actions:** PendingAction, VaultPendingAction and LongPendingAction have now a variable to keep the value of the security deposit done in the initialise action
* **actions:** `getPositionValue` now returns a signed int which is negative in case of bad debt

### Features

* **actions:** security deposit ([#137](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/137)) ([c09d964](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c09d96427a7e127a7020c3796e21cb629291650d))
* add minimum long position value ([#167](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/167)) ([6ffb50a](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6ffb50aab35087c83a2bebd607e5751d5e2bddce))
* add wusdn and test ([#156](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/156)) ([3ca9024](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3ca9024339dd901b5ac790944b1c5578431bb6cb))
* **rebase:** change default values for rebase parameters ([#162](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/162)) ([27a9ccd](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/27a9ccde34715035196375aa53086a3623647b57))
* **sdex-burn:** depositing assets in the protocol now requires the user to have enough SDEX in his wallet to support the burn fee. ([6d08982](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6d089823c4e5fd95498d80062dd7977b7fdc3a88))
* **storage:** update initial target usdn price ([#168](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/168)) ([bd5568b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/bd5568b1e4286750488efe826cc619248dd2eb43))
* **usdn:** add functions to transfer, mint, burn shares ([#163](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/163)) ([f9bc31c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f9bc31c79ae1f9a6b056ace665441653e1264f40))


### Bug Fixes

* **actions:** fix handling of bad debt in case of single position liq ([#160](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/160)) ([d60d99b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d60d99b415221ce883600efdd232b747026cb73b))
* **withdraw:** use USDN shares for withdrawal input and burn ([#173](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/173)) ([9f1879f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/9f1879f73bb02e9f93f6291ae0dec62d3fe342df))

## [0.11.1](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.11.0...v0.11.1) (2024-03-25)


### Bug Fixes

* **middleware:** infinite loop in mock contract ([#164](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/164)) ([64ef1a0](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/64ef1a0b5c616d112c6c02b2df0b81fe25b29227))

## [0.11.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.10.0...v0.11.0) (2024-03-21)


### ⚠ BREAKING CHANGES

* **middleware:** removed `getPythDecimals` from oracle middleware
* **actions:** `initiateDeposit`, `validateDeposit`, `initiateWithdrawal`, `validateWithdrawal`, `initiateOpenPosition`, `validateOpenPosition`, `initiateClosePosition` and `validateClosePosition` now take a `PreviousActionsData` struct as last argument. `getActionablePendingAction` for now returns a single action and its corresponding rawIndex. `DoubleEndedQueue` returns a second argument with the raw index for methods `front`, `back` and `at`.
* `getTotalExpoByTick` now doesn't require the tick version anymore, `getPositionsInTick` now doesn't require the tick version anymore, `getLongPositionsLength` was removed as it was doing the same thing as `getPositionsInTick`
* new parameter `timestamp` in events `InitiatedDeposit`, `InitiatedWithdrawal`, `ValidatedDeposit` and `ValidatedWithdrawal`

### Features

* **actions:** manually validate pending actions ([#145](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/145)) ([84e3d2f](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/84e3d2f31c909dff93f072a037d47f0950b2bc52))
* add timestamp in emit ([eb11fbe](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/eb11fbeeb8ac7e921c3b3d48f7fef88e05b1eb79))
* **middleware:** use cached pyth price ([#152](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/152)) ([e9cc402](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/e9cc4022a09a504ed99f00002a11c5820ab43251))
* **positions:** expo limits mechanism ([#103](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/103)) ([eb4fe56](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/eb4fe568c53c5be5977342da87b39f8f51054b8f))


### Bug Fixes

* disable slither false positive ([2672f14](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2672f14394b90b9eb39170228d656abe3055f034))
* **funding:** decimals in returned values ([#150](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/150)) ([18a58a7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/18a58a747289bcbc11c642cbfdfaeecfa8369a86))
* **gas-test:** fix liquidation gas usage test ([2672f14](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2672f14394b90b9eb39170228d656abe3055f034))
* **middleware:** unify types and fix some bugs ([#141](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/141)) ([cfae831](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/cfae831b3b6fc4c7a36ba9cb3d3378a2be88b1a7))


### Code Refactoring

* remove tick version parameter to external functions and delete duplicated function ([2672f14](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2672f14394b90b9eb39170228d656abe3055f034))

## [0.10.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.9.0...v0.10.0) (2024-03-14)


### ⚠ BREAKING CHANGES

* **actions:** `initiateDeposit`, `validateDeposit`, `initiateWithdrawal`, `validateWithdrawal`, `initiateOpenPosition`, `validateOpenPosition`, `initiateClosePosition` and `validateClosePosition` now take a `PreviousActionsData` struct as last argument. `getActionablePendingAction` for now returns a single action and its corresponding rawIndex. `DoubleEndedQueue` returns a second argument with the raw index for methods `front`, `back` and `at`.
* **close-long:** Position and PendingAction structs do not return the leverage anymore, they have the position expo instead
* **core:** changed visibility of funding and fundingAsset functions ([#143](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/143))
* **core:** view functions for balances now consider funding and fees ([#131](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/131))
* **usdn:** `ADJUSTMENT_ROLE` becomes `REBASER_ROLE`, `adjustDivisor` becomes `rebase`, `DivisorAdjusted` becomes `Rebase`

### Features

* **actions:** separated external functions in multiple internal functions ([#135](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/135)) ([3bdab81](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3bdab81c068e502712d5c5e0a8461978b5c34f18))
* **close-long:** add the ability to partially close a position ([#130](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/130)) ([62ff252](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/62ff252d668f5bd54741ae1b2cfa9f341f33654d))
* **core:** changed visibility of funding and fundingAsset functions ([#143](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/143)) ([d63cb41](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d63cb41415a8e53a5632c71b22d6862128a3b7e6))
* **core:** view functions for balances now consider funding and fees ([#131](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/131)) ([4c323c9](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4c323c92d2945decabc27e6739da516a41aa02be))
* **usdn:** add automatic rebase ([#124](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/124)) ([007df26](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/007df26c1f050546c7372ffedd5a2d2845e88248))


### Bug Fixes

* **assettotransfer:** fix the double subtraction in asset to transfer when validating a close position ([#138](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/138)) ([8bc712c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/8bc712ce71bf2c81fcf311b6fe08431fa0d65f60))
* **position-totalexpo:** use the liq price without penalty to calculate the position total expo ([#134](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/134)) ([90b2ca4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/90b2ca4f17bcf236dd09ec59a6bbce4f1bb3680e))


### Code Refactoring

* **actions:** allow to pass a list of pending actions data ([#133](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/133)) ([efaea43](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/efaea43f8a2a38e39f8f41a21f92eb5c9649c832))

## [0.9.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.8.0...v0.9.0) (2024-03-07)


### ⚠ BREAKING CHANGES

* **positions:** Position and PendingAction structs do not return the leverage anymore, they have the position expo instead

### Features

* **priceProcessing:** entry/exit fees and oracle price confidence ratio ([#82](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/82)) ([48d897b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/48d897b010b33866fdac85ce667d5b03e9c65741))
* update Hermes api endpoint to Ra2 Pyth node ([#125](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/125)) ([0c3dd15](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/0c3dd15884cb91814d411b7aa947c437f6da3aef))


### Code Refactoring

* **positions:** replace the leverage by the position expo in position and action structs ([#113](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/113)) ([7317c4d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7317c4da0669405cdd286a033017157429963630))

## [0.8.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.7.0...v0.8.0) (2024-02-29)


### ⚠ BREAKING CHANGES

* getPositionValue now expects a timestamp parameter
* **protocol:** view and admin functions ([#93](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/93))
* removed default position and added protection in funding calculation ([#102](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/102))

### Features

* **protocol:** view and admin functions ([#93](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/93)) ([d3dfaf2](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/d3dfaf2f4f810c59b24cc875b72dea14c036418e))
* removed default position and added protection in funding calculation ([#102](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/102)) ([5907e66](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/5907e66d5d84acfa71cc4ed347aaaee48015c594))


### Bug Fixes

* handling of the balance updates ([#101](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/101)) ([54d6025](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/54d60256846fcd7fd67557e9310b8b6a52054c8f))

## [0.7.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.6.0...v0.7.0) (2024-02-22)


### ⚠ BREAKING CHANGES

* **LiquidationRewards:** Implement the LiquidationRewardsManager contract and transfer liquidation rewards to the liquidator ([#91](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/91))
* the constructor now takes feeCollector address

### Features

* add protocol fee ([#90](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/90)) ([088810c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/088810ca650b38e01d7cf6f08ee032b369fe94e5))
* **LiquidationRewards:** Implement the LiquidationRewardsManager contract and transfer liquidation rewards to the liquidator ([#91](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/91)) ([c860fa6](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c860fa6799b848cf5aee78b9263ea2dddb2300e6))


### Bug Fixes

* Adjust the total expo when the leverage of the position change on validation ([#104](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/104)) ([908c8e1](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/908c8e1b5638bb9295af24b42daa0fc9c281c665))
* **ema:** protection when secondElapsed &gt;= EMAPeriod ([#99](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/99)) ([c3bf2b3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/c3bf2b326b1294f869ac0bae63f36899bc7b06e8))
* **middleware:** validation logic for liquidation ([#95](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/95)) ([681ffb3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/681ffb30677908df35f34429087246a3c43d9371))

## [0.6.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.5.0...v0.6.0) (2024-02-15)


### ⚠ BREAKING CHANGES

* transfer remaining collateral to vault upon liquidation ([#89](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/89))
* **events:** `Position` has no `startPrice` anymore, `InitiatedOpenPosition` and `ValidatedOpenPosition` have different fields
* **middleware:** some unused errors don't exist anymore

### Features

* transfer remaining collateral to vault upon liquidation ([#89](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/89)) ([92f43e7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/92f43e79538872afed48f441a41b44d9472db302))
* update position tick if leverage exceeds max leverage ([#76](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/76)) ([aad0e50](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/aad0e501d0787e7e1cc67d7f25828a34379f0617))


### Bug Fixes

* **liquidation:** use neutral price and liquidate whenever possible ([#94](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/94)) ([92f13b5](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/92f13b55eca6e351e928c046734d56fdb68b5621))
* **middleware:** remove unused errors ([#83](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/83)) ([6a95a11](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/6a95a11ce822fddd4e2f5b804ef796d9986fa61f))
* only pass required ether to middleware and refund excess ([#87](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/87)) ([7c777e4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/7c777e4b8c62e7729ca6f1c1b788195bdc9c7d1a))


### Code Refactoring

* **events:** remove unused or unneeded fields from events and structs ([#88](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/88)) ([672e4f7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/672e4f7c07bf9ec305d0c3c4e70cc631e367e73d))

## [0.5.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.4.0...v0.5.0) (2024-02-08)


### ⚠ BREAKING CHANGES

* **long:** the input desired liquidation price to `initiateOpenPosition` is now considered to already include the liquidation penalty.
* **pending:** the queue `PendingActions` now store `Validate...` protocol actions
* **long:** initiateClosePosition removes the position from the tick/protocol ([#70](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/70))
* **liquidation-core:** fix two calculation bugs with liquidation tick selection and sign of `fundingAsset` ([#72](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/72))
* **interfaces:** some public functions are now private
* **middleware:** oracle middleware minor changes ([#66](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/66))
* **UsdnProtocolLong:** add liquidation price in LiquidatedTick event ([#65](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/65))

### Features

* **interfaces:** create and refactor interfaces ([#64](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/64)) ([e6dbad5](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/e6dbad5c4510550fd2b63cfb00d09080a15073c4))
* **middleware:** mock oracle middleware for fork environment ([#78](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/78)) ([97bc06d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/97bc06dd4581a468098df3f8cead9b3006b06d7e))
* new funding calculation ([#73](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/73)) ([740f4a2](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/740f4a21bc9385890b146fe7a24f36285489bcdc))
* **storage:** add two functions to fetch internal variables ([#75](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/75)) ([b81a6cb](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b81a6cb8d0d2be2e477cc686da69f92f3926402d))
* **UsdnProtocolLong:** add liquidation price in LiquidatedTick event ([#65](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/65)) ([32a6301](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/32a63019b2fff36ac036e4c320bccf855ab005b7))


### Bug Fixes

* **liquidation-core:** fix two calculation bugs with liquidation tick selection and sign of `fundingAsset` ([#72](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/72)) ([df335ae](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/df335ae288a79f5fe5f80ea374001a05a126c116))
* **long:** desired liq price now includes liquidation penalty ([#80](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/80)) ([f842ca7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f842ca7eec306583029fb0a606bc3a194531c796))
* **pending:** remove pending action from third party user when it gets validated ([#81](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/81)) ([da0350b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/da0350b994ea513d1f31e0bab126ea8d57a6e7ad))
* **pending:** store `Validate...` protocol actions in pending actions ([#79](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/79)) ([79bfe56](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/79bfe56548b32d1a811b6e48113adaebab3fca05))
* **pending:** user validating their own action while it's actionable by anyone ([#77](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/77)) ([df5b8c2](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/df5b8c24582d110d111cdac1706f5f35ca6b27a8))


### Code Refactoring

* **long:** initiateClosePosition removes the position from the tick/protocol ([#70](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/70)) ([a3f87c6](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a3f87c62c459cfb47b6380791316416f85b913fa))
* **middleware:** oracle middleware minor changes ([#66](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/66)) ([ff39bb3](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ff39bb38b2f3c2e2e6e2ead29e8969c418015d7c))

## [0.4.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.3.0...v0.4.0) (2024-02-01)


### ⚠ BREAKING CHANGES

* **middleware:** wsteth oracle ([#62](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/62))
* **core:** make getActionablePendingAction a view function ([#61](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/61))
* **long:** events related to long positions now emit the tick version, many functions require tick, tick version and index to identify a position

### Features

* **liquidation:** events ([#59](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/59)) ([b5cfaab](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b5cfaab94ecfcd6f8890a227db4fe99dfb0d0116))
* **middleware:** wsteth oracle ([#62](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/62)) ([2682a90](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/2682a90a6e014f89438043c495690183413d8619))
* **pending:** remove stale pending actions ([#69](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/69)) ([787e286](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/787e286b6472a9994b63b2403612366ecadecf84))


### Code Refactoring

* **core:** make getActionablePendingAction a view function ([#61](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/61)) ([146adf8](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/146adf879a59b61e868049ee09f888f53eeadf4c))
* **long:** add tick version as part of unique position identifier ([#57](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/57)) ([308a31e](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/308a31e47f0478569b4b0905ae2bae48438886a7))

## [0.3.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.2.0...v0.3.0) (2024-01-25)


### ⚠ BREAKING CHANGES

* liquidation multiplier ([#42](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/42))
* **long:** calculate position value according to new formula ([#49](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/49))

### Features

* add oracle middleware ABI ([#55](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/55)) ([739b363](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/739b3634f39ff3ac27bbb33f892a23c8272dff5a))
* liquidation multiplier ([#42](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/42)) ([765446e](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/765446e39e86a7db1775312b4103b78795a63d6a))
* liquidations ([#44](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/44)) ([b9da1b4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b9da1b4320080abae2bce122d568d97dd045ce6c))
* **long:** calculate position value according to new formula ([#49](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/49)) ([b8f12d2](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b8f12d2792aa41be3ea9b6164a0e2451b783a5d6))


### Bug Fixes

* update flake.lock ([#51](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/51)) ([b991c33](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/b991c33dfa0b29fc1b1f1c68897a10422a28e52f))

## [0.2.0](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.1.3...v0.2.0) (2024-01-18)


### ⚠ BREAKING CHANGES

* **deposit-withdraw:** deposit and withdraw amount calculations ([#43](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/43))
* **TickMath:** increase precision to 0.01% per tick ([#36](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/36))

### Features

* Oracle middleware ([#33](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/33)) ([af59706](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/af59706de11fba24a0579e65bd6b13f02ef26c5b))
* update deploy script with oracle middleware implementation ([#48](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/48)) ([68d9f7d](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/68d9f7db04e50d38dc06a260dd6365ca26ae9e48))


### Bug Fixes

* check safety margin ([#41](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/41)) ([ae001fd](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/ae001fd725edd3880a1a734d053098917357d530))
* **deposit-withdraw:** deposit and withdraw amount calculations ([#43](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/43)) ([f7a9d7b](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f7a9d7b7c1bc750f5181ac1e76d4c3a87c597f9b))
* USDN mint amount ([#38](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/38)) ([4bd98d1](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4bd98d12dc0e4c1db5d92b0583f14f1719bb5432))


### Code Refactoring

* **TickMath:** increase precision to 0.01% per tick ([#36](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/36)) ([3524339](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/3524339b4df67b7ba020348768bda2420b1dd8fc))

## [0.1.3](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.1.2...v0.1.3) (2024-01-09)


### Features

* script to setup fork ([#34](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/34)) ([26346f9](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/26346f9e35d8f0ba4edf5f4ad8cd79de88ce8b4a))

## [0.1.2](https://github.com/SmarDex-Ecosystem/usdn-contracts/compare/v0.1.1...v0.1.2) (2024-01-08)


### Features

* add tick math library ([a23ff3a](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a23ff3a9286e4423f38b22f985582ecef1a8839d))
* **ci:** using app token with release-please action ([#26](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/26)) ([e046e53](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/e046e5308a1eb0efcf712ab893e5808277455a6b))
* deposit and withdraw, modularity, fixtures and more ([#11](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/11)) ([66e83c8](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/66e83c84454ad85d1d07bede6eb0c5f557cc865d))
* open/close long ([#12](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/12)) ([4703fd9](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4703fd9baaebc4dffa7cf8f0b86362bc1570b961))
* **ticks:** add custom error for invalid tickSpacing ([a1eefde](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/a1eefde0512d470b7aa06319b949f0c8b4329a92))
* USDN token ([#4](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/4)) ([4bedad4](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/4bedad46728b6e073abe5532524eedf74fd1fb48))
* vault side ([#8](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/8)) ([297eddc](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/297eddc8f06b02971696006ca5d6123592622868))


### Bug Fixes

* add missing `burn` and `burnFrom` to `IUsdn` ([#6](https://github.com/SmarDex-Ecosystem/usdn-contracts/issues/6)) ([f4397a1](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/f4397a1178c0b9f83ceea2f38d710bd5be3af7bf))


### Performance Improvements

* gas optim for double comparison ([9d8d7b7](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/9d8d7b73c010c004a3e6efb6f3b08468f4e1813f))
* improve max tick ([38bf32c](https://github.com/SmarDex-Ecosystem/usdn-contracts/commit/38bf32c3e2f2bc39c7ecdf6a75318ddf1dbb9242))
