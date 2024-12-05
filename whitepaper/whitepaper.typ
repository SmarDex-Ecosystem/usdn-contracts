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
    This paper present a new decentralized protocol proposing two defi products : making yield by being exposed in dollar and long leverage trading.
    It covers the mathematical principles and choices for both products.
    A new token is introduced, USDN, a tradable ERC20 and making value over time.
    It explain how we store value in a vault for the synthetic dollar side and then how we store long and calculate their profit and loss (PnL).
    This whitepaper describes the mechanics of funding and imbalance limits to ensure the right behavior of the protocol.
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
The underlying asset deposited to mint USDN tokens is used as liquidity for the structure product to enable leveraged trading.
This asset can indirectly bring incentives to users and be able to use financial products.
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

== Token Minting

USDN tokens are minted whenever a deposit is made into the protocol's vault. The amount of minted USDN $A_"usdn"$ is
calculated by dividing the dollar value of the deposited assets by the USDN price:

$ A_"usdn" = frac(A_"asset" P_"asset", P_"usdn") $ <eq:usdn_minting>

Taking into account @eq:usdn_price, the minting formula can be rewritten as:

$ A_"usdn" = frac(A_"asset" S_"tot", B_"vault") $

== Token Burning

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

= Long

== Tick

== PNL

= Funding

= Imbalance