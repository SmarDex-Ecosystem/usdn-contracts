# Changelog

## [0.10.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.9.0...v0.10.0) (2024-03-14)


### ⚠ BREAKING CHANGES

* **actions:** `initiateDeposit`, `validateDeposit`, `initiateWithdrawal`, `validateWithdrawal`, `initiateOpenPosition`, `validateOpenPosition`, `initiateClosePosition` and `validateClosePosition` now take a `PreviousActionsData` struct as last argument. `getActionablePendingAction` for now returns a single action and its corresponding rawIndex. `DoubleEndedQueue` returns a second argument with the raw index for methods `front`, `back` and `at`.
* **close-long:** Position and PendingAction structs do not return the leverage anymore, they have the position expo instead
* **core:** changed visibility of funding and fundingAsset functions ([#143](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/143))
* **core:** view functions for balances now consider funding and fees ([#131](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/131))
* **usdn:** `ADJUSTMENT_ROLE` becomes `REBASER_ROLE`, `adjustDivisor` becomes `rebase`, `DivisorAdjusted` becomes `Rebase`

### Features

* **actions:** separated external functions in multiple internal functions ([#135](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/135)) ([3bdab81](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/3bdab81c068e502712d5c5e0a8461978b5c34f18))
* **close-long:** add the ability to partially close a position ([#130](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/130)) ([62ff252](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/62ff252d668f5bd54741ae1b2cfa9f341f33654d))
* **core:** changed visibility of funding and fundingAsset functions ([#143](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/143)) ([d63cb41](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/d63cb41415a8e53a5632c71b22d6862128a3b7e6))
* **core:** view functions for balances now consider funding and fees ([#131](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/131)) ([4c323c9](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/4c323c92d2945decabc27e6739da516a41aa02be))
* **usdn:** add automatic rebase ([#124](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/124)) ([007df26](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/007df26c1f050546c7372ffedd5a2d2845e88248))


### Bug Fixes

* **assettotransfer:** fix the double subtraction in asset to transfer when validating a close position ([#138](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/138)) ([8bc712c](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/8bc712ce71bf2c81fcf311b6fe08431fa0d65f60))
* **position-totalexpo:** use the liq price without penalty to calculate the position total expo ([#134](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/134)) ([90b2ca4](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/90b2ca4f17bcf236dd09ec59a6bbce4f1bb3680e))


### Code Refactoring

* **actions:** allow to pass a list of pending actions data ([#133](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/133)) ([efaea43](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/efaea43f8a2a38e39f8f41a21f92eb5c9649c832))

## [0.9.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.8.0...v0.9.0) (2024-03-07)


### ⚠ BREAKING CHANGES

* **positions:** Position and PendingAction structs do not return the leverage anymore, they have the position expo instead

### Features

* **priceProcessing:** entry/exit fees and oracle price confidence ratio ([#82](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/82)) ([48d897b](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/48d897b010b33866fdac85ce667d5b03e9c65741))
* update Hermes api endpoint to Ra2 Pyth node ([#125](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/125)) ([0c3dd15](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/0c3dd15884cb91814d411b7aa947c437f6da3aef))


### Code Refactoring

* **positions:** replace the leverage by the position expo in position and action structs ([#113](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/113)) ([7317c4d](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/7317c4da0669405cdd286a033017157429963630))

## [0.8.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.7.0...v0.8.0) (2024-02-29)


### ⚠ BREAKING CHANGES

* getPositionValue now expects a timestamp parameter
* **protocol:** view and admin functions ([#93](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/93))
* removed default position and added protection in funding calculation ([#102](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/102))

### Features

* **protocol:** view and admin functions ([#93](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/93)) ([d3dfaf2](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/d3dfaf2f4f810c59b24cc875b72dea14c036418e))
* removed default position and added protection in funding calculation ([#102](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/102)) ([5907e66](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/5907e66d5d84acfa71cc4ed347aaaee48015c594))


### Bug Fixes

* handling of the balance updates ([#101](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/101)) ([54d6025](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/54d60256846fcd7fd67557e9310b8b6a52054c8f))

## [0.7.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.6.0...v0.7.0) (2024-02-22)


### ⚠ BREAKING CHANGES

* **LiquidationRewards:** Implement the LiquidationRewardsManager contract and transfer liquidation rewards to the liquidator ([#91](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/91))
* the constructor now takes feeCollector address

### Features

* add protocol fee ([#90](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/90)) ([088810c](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/088810ca650b38e01d7cf6f08ee032b369fe94e5))
* **LiquidationRewards:** Implement the LiquidationRewardsManager contract and transfer liquidation rewards to the liquidator ([#91](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/91)) ([c860fa6](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/c860fa6799b848cf5aee78b9263ea2dddb2300e6))


### Bug Fixes

* Adjust the total expo when the leverage of the position change on validation ([#104](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/104)) ([908c8e1](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/908c8e1b5638bb9295af24b42daa0fc9c281c665))
* **ema:** protection when secondElapsed &gt;= EMAPeriod ([#99](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/99)) ([c3bf2b3](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/c3bf2b326b1294f869ac0bae63f36899bc7b06e8))
* **middleware:** validation logic for liquidation ([#95](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/95)) ([681ffb3](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/681ffb30677908df35f34429087246a3c43d9371))

## [0.6.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.5.0...v0.6.0) (2024-02-15)


### ⚠ BREAKING CHANGES

* transfer remaining collateral to vault upon liquidation ([#89](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/89))
* **events:** `Position` has no `startPrice` anymore, `InitiatedOpenPosition` and `ValidatedOpenPosition` have different fields
* **middleware:** some unused errors don't exist anymore

### Features

* transfer remaining collateral to vault upon liquidation ([#89](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/89)) ([92f43e7](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/92f43e79538872afed48f441a41b44d9472db302))
* update position tick if leverage exceeds max leverage ([#76](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/76)) ([aad0e50](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/aad0e501d0787e7e1cc67d7f25828a34379f0617))


### Bug Fixes

* **liquidation:** use neutral price and liquidate whenever possible ([#94](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/94)) ([92f13b5](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/92f13b55eca6e351e928c046734d56fdb68b5621))
* **middleware:** remove unused errors ([#83](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/83)) ([6a95a11](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/6a95a11ce822fddd4e2f5b804ef796d9986fa61f))
* only pass required ether to middleware and refund excess ([#87](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/87)) ([7c777e4](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/7c777e4b8c62e7729ca6f1c1b788195bdc9c7d1a))


### Code Refactoring

* **events:** remove unused or unneeded fields from events and structs ([#88](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/88)) ([672e4f7](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/672e4f7c07bf9ec305d0c3c4e70cc631e367e73d))

## [0.5.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.4.0...v0.5.0) (2024-02-08)


### ⚠ BREAKING CHANGES

* **long:** the input desired liquidation price to `initiateOpenPosition` is now considered to already include the liquidation penalty.
* **pending:** the queue `PendingActions` now store `Validate...` protocol actions
* **long:** initiateClosePosition removes the position from the tick/protocol ([#70](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/70))
* **liquidation-core:** fix two calculation bugs with liquidation tick selection and sign of `fundingAsset` ([#72](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/72))
* **interfaces:** some public functions are now private
* **middleware:** oracle middleware minor changes ([#66](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/66))
* **UsdnProtocolLong:** add liquidation price in LiquidatedTick event ([#65](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/65))

### Features

* **interfaces:** create and refactor interfaces ([#64](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/64)) ([e6dbad5](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/e6dbad5c4510550fd2b63cfb00d09080a15073c4))
* **middleware:** mock oracle middleware for fork environment ([#78](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/78)) ([97bc06d](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/97bc06dd4581a468098df3f8cead9b3006b06d7e))
* new funding calculation ([#73](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/73)) ([740f4a2](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/740f4a21bc9385890b146fe7a24f36285489bcdc))
* **storage:** add two functions to fetch internal variables ([#75](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/75)) ([b81a6cb](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/b81a6cb8d0d2be2e477cc686da69f92f3926402d))
* **UsdnProtocolLong:** add liquidation price in LiquidatedTick event ([#65](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/65)) ([32a6301](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/32a63019b2fff36ac036e4c320bccf855ab005b7))


### Bug Fixes

* **liquidation-core:** fix two calculation bugs with liquidation tick selection and sign of `fundingAsset` ([#72](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/72)) ([df335ae](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/df335ae288a79f5fe5f80ea374001a05a126c116))
* **long:** desired liq price now includes liquidation penalty ([#80](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/80)) ([f842ca7](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/f842ca7eec306583029fb0a606bc3a194531c796))
* **pending:** remove pending action from third party user when it gets validated ([#81](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/81)) ([da0350b](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/da0350b994ea513d1f31e0bab126ea8d57a6e7ad))
* **pending:** store `Validate...` protocol actions in pending actions ([#79](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/79)) ([79bfe56](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/79bfe56548b32d1a811b6e48113adaebab3fca05))
* **pending:** user validating their own action while it's actionable by anyone ([#77](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/77)) ([df5b8c2](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/df5b8c24582d110d111cdac1706f5f35ca6b27a8))


### Code Refactoring

* **long:** initiateClosePosition removes the position from the tick/protocol ([#70](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/70)) ([a3f87c6](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/a3f87c62c459cfb47b6380791316416f85b913fa))
* **middleware:** oracle middleware minor changes ([#66](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/66)) ([ff39bb3](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/ff39bb38b2f3c2e2e6e2ead29e8969c418015d7c))

## [0.4.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.3.0...v0.4.0) (2024-02-01)


### ⚠ BREAKING CHANGES

* **middleware:** wsteth oracle ([#62](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/62))
* **core:** make getActionablePendingAction a view function ([#61](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/61))
* **long:** events related to long positions now emit the tick version, many functions require tick, tick version and index to identify a position

### Features

* **liquidation:** events ([#59](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/59)) ([b5cfaab](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/b5cfaab94ecfcd6f8890a227db4fe99dfb0d0116))
* **middleware:** wsteth oracle ([#62](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/62)) ([2682a90](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/2682a90a6e014f89438043c495690183413d8619))
* **pending:** remove stale pending actions ([#69](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/69)) ([787e286](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/787e286b6472a9994b63b2403612366ecadecf84))


### Code Refactoring

* **core:** make getActionablePendingAction a view function ([#61](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/61)) ([146adf8](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/146adf879a59b61e868049ee09f888f53eeadf4c))
* **long:** add tick version as part of unique position identifier ([#57](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/57)) ([308a31e](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/308a31e47f0478569b4b0905ae2bae48438886a7))

## [0.3.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.2.0...v0.3.0) (2024-01-25)


### ⚠ BREAKING CHANGES

* liquidation multiplier ([#42](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/42))
* **long:** calculate position value according to new formula ([#49](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/49))

### Features

* add oracle middleware ABI ([#55](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/55)) ([739b363](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/739b3634f39ff3ac27bbb33f892a23c8272dff5a))
* liquidation multiplier ([#42](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/42)) ([765446e](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/765446e39e86a7db1775312b4103b78795a63d6a))
* liquidations ([#44](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/44)) ([b9da1b4](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/b9da1b4320080abae2bce122d568d97dd045ce6c))
* **long:** calculate position value according to new formula ([#49](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/49)) ([b8f12d2](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/b8f12d2792aa41be3ea9b6164a0e2451b783a5d6))


### Bug Fixes

* update flake.lock ([#51](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/51)) ([b991c33](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/b991c33dfa0b29fc1b1f1c68897a10422a28e52f))

## [0.2.0](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.1.3...v0.2.0) (2024-01-18)


### ⚠ BREAKING CHANGES

* **deposit-withdraw:** deposit and withdraw amount calculations ([#43](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/43))
* **TickMath:** increase precision to 0.01% per tick ([#36](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/36))

### Features

* Oracle middleware ([#33](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/33)) ([af59706](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/af59706de11fba24a0579e65bd6b13f02ef26c5b))
* update deploy script with oracle middleware implementation ([#48](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/48)) ([68d9f7d](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/68d9f7db04e50d38dc06a260dd6365ca26ae9e48))


### Bug Fixes

* check safety margin ([#41](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/41)) ([ae001fd](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/ae001fd725edd3880a1a734d053098917357d530))
* **deposit-withdraw:** deposit and withdraw amount calculations ([#43](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/43)) ([f7a9d7b](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/f7a9d7b7c1bc750f5181ac1e76d4c3a87c597f9b))
* USDN mint amount ([#38](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/38)) ([4bd98d1](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/4bd98d12dc0e4c1db5d92b0583f14f1719bb5432))


### Code Refactoring

* **TickMath:** increase precision to 0.01% per tick ([#36](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/36)) ([3524339](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/3524339b4df67b7ba020348768bda2420b1dd8fc))

## [0.1.3](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.1.2...v0.1.3) (2024-01-09)


### Features

* script to setup fork ([#34](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/34)) ([26346f9](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/26346f9e35d8f0ba4edf5f4ad8cd79de88ce8b4a))

## [0.1.2](https://github.com/Blockchain-RA2-Tech/usdn-contracts/compare/v0.1.1...v0.1.2) (2024-01-08)


### Features

* add tick math library ([a23ff3a](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/a23ff3a9286e4423f38b22f985582ecef1a8839d))
* **ci:** using app token with release-please action ([#26](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/26)) ([e046e53](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/e046e5308a1eb0efcf712ab893e5808277455a6b))
* deposit and withdraw, modularity, fixtures and more ([#11](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/11)) ([66e83c8](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/66e83c84454ad85d1d07bede6eb0c5f557cc865d))
* open/close long ([#12](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/12)) ([4703fd9](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/4703fd9baaebc4dffa7cf8f0b86362bc1570b961))
* **ticks:** add custom error for invalid tickSpacing ([a1eefde](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/a1eefde0512d470b7aa06319b949f0c8b4329a92))
* USDN token ([#4](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/4)) ([4bedad4](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/4bedad46728b6e073abe5532524eedf74fd1fb48))
* vault side ([#8](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/8)) ([297eddc](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/297eddc8f06b02971696006ca5d6123592622868))


### Bug Fixes

* add missing `burn` and `burnFrom` to `IUsdn` ([#6](https://github.com/Blockchain-RA2-Tech/usdn-contracts/issues/6)) ([f4397a1](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/f4397a1178c0b9f83ceea2f38d710bd5be3af7bf))


### Performance Improvements

* gas optim for double comparison ([9d8d7b7](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/9d8d7b73c010c004a3e6efb6f3b08468f4e1813f))
* improve max tick ([38bf32c](https://github.com/Blockchain-RA2-Tech/usdn-contracts/commit/38bf32c3e2f2bc39c7ecdf6a75318ddf1dbb9242))
