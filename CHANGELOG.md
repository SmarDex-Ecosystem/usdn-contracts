# Changelog

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
