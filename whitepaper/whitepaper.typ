#import "template.typ": template

#show: template.with(
  title: [Ultimate Synthetic Delta Neutral],
  authors: (
    (
      name: "TBD",
      institution: "RA2 Tech SA",
      location: "Switzerland",
      mail: "info@ra2.tech",
    ),
  ),
  abstract: [
    Dollar-backed stablecoins have long been a cornerstone of the decentralized finance (DeFi) ecosystem, but they are subject to the
    same value depreciation as the US dollar due to inflation.
    Yield-bearing synthetic dollar tokens have been proposed in the past, but they suffer from centralization and lack
    of transparency.
    We present a novel protocol comprised of two DeFi products: an algorithmic yield-bearing synthetic dollar token
    (USDN) and a decentralized long perpetual futures trading platform. We describe the mathematical principles
    supporting the protocol and the interaction between both products.
    This research shows that a fully decentralized and transparent model can be used to support a yield-bearing
    synthetic dollar token while remaining economically viable and gas-efficient.
  ],
  keywords: ("DeFi", "Blockchain", "Synthetic Assets", "Delta Neutral")
)

= Introduction

The decentralized finance (DeFi) ecosystem has long sought alternatives to fiat-backed tokens, aiming to provide users
with assets that combine dollar-like stability with yield generation. However, existing solutions, particularly stablecoins, suffer
from inherent flaws: they are often centralized, opaque, and yield-free for holders.

USDN aims to solve this problem by operating a fully decentralized structured product.
Its architecture eliminates dependencies on centralized exchanges (CEXs) and custodial intermediaries.
Instead, users interact with smart contracts to mint or redeem USDN tokens, as well as to open long perpetual positions.
The underlying asset deposited to mint USDN tokens is used as liquidity for the structured product to enable leveraged trading.
The first deployment of this protocol uses the wrapped staked ETH (wstETH) from #cite(<lido-wsteth>, form: "prose") as underlying asset.
This means that we combine the yield of the protocol with that of staking ETH automatically.

= Protocol architecture

= USDN Token

== Overview

The USDN token is a synthetic USD token designed to approximate the value of one US dollar while delivering consistent
returns to its holders. Unlike a stablecoin, USDN does not claim to maintain a rigid peg to \$1. Instead, it oscillates
slightly above or below this reference value, supported by market forces and the protocol's innovative mechanisms.

The value of USDN comes from assets (a specific ERC20 token) stored in the protocol's vault. This can be any token for
which a price oracle is available and for which the balance does not change over time without transfer. For the first
release of the protocol, the token is wstETH.

== Price

Due to the algorithmic nature of the USDN token, its price in dollars $P_"usdn"$ can be calculated using the following
formula:

$ P_"usdn" = frac(B_"vault" P_"asset", S_"tot") $ <eq:usdn_price>

where $B_"vault"$ is the balance of assets held in the protocol's vault, $P_"asset"$ is the price of the asset token in
USD, and $S_"tot"$ is the total supply of USDN tokens.

== Token Minting <seq:token_minting>

USDN tokens are minted whenever a deposit is made into the protocol's vault. The amount of minted USDN $A_"usdn"$ is
calculated by dividing the dollar value of the deposited assets by the USDN price:

$ A_"usdn" = frac(A_"asset" P_"asset", P_"usdn") $ <eq:usdn_minting>

Taking into account @eq:usdn_price, the minting formula can be rewritten as:

$ A_"usdn" = frac(A_"asset" S_"tot", B_"vault") $

== Token Burning <seq:token_burning>

When assets are removed from the protocol's vault, USDN tokens are burned in proportion to the withdrawn amount,
following @eq:usdn_minting. Thus, for a given amount of USDN to be burned, the corresponding withdrawn assets amount is:

$ A_"asset" = frac(A_"usdn" P_"usdn", P_"asset") = frac(A_"usdn" B_"vault", S_"tot") $

== Yield Sources

From @eq:usdn_price, it is clear that the USDN price is influenced by the total assets held in the protocol's vault.
As such, if the vault balance increases as a result of position fees, losses from long positions, or funding payments,
the USDN price will rise. When a certain threshold is reached, the token rebases to a price slightly above \$1 by
increasing the total supply and balance of each holder. This increase in balance represents the yield of the USDN token.
The rebase mechanism ensures that yields do not induce a price that significantly exceeds the value of \$1. There is no
balance and total supply adjustment (rebase) if the price falls below \$1.

= Vault

The vault manages the supply of USDN tokens. The two main actions of the vault are deposits and withdrawals.

The deposit action allows to lock assets into the vault and mint a proportional amount of USDN tokens by providing an oracle price for the asset token.
It follows the formula described in @seq:token_minting.

The withdrawal action allows to redeem USDN tokens for an equivalent dollar amount of assets from the vault.
It follows the formula described in @seq:token_burning.

= Long

== Tick

== PNL

= Funding

= Imbalance