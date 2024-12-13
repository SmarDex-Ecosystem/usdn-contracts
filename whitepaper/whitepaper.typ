#import "template.typ": template
#import "glossary.typ": glossary
#import "@preview/glossarium:0.5.1": make-glossary, register-glossary, print-glossary, gls, glspl

#show: make-glossary
#register-glossary(glossary)

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
    Dollar-backed stablecoins have long been a cornerstone of the decentralized finance (DeFi) ecosystem, but they are
    subject to the same value depreciation as the US dollar due to inflation.
    Yield-bearing synthetic dollar tokens have been proposed in the past, but they suffer from centralization and lack
    of transparency.
    We present a novel protocol comprised of two DeFi products: an algorithmic yield-bearing synthetic dollar token
    (USDN) and a decentralized long perpetual futures trading platform. We describe the mathematical principles
    supporting the protocol and the interaction between both products.
    This research shows that a fully decentralized and transparent model can be used to support a yield-bearing
    synthetic dollar token while remaining economically viable and gas-efficient.
  ],
  keywords: ("DeFi", "Blockchain", "Synthetic Assets", "Delta Neutral"),
)

// note: use the `_` symbol between quantities and the corresponding unit to insert a thin non-breakable space.
// e.g. `1_wstETH` will render as `1 wstETH` but no line break will be allowed between the number and the unit.

= Introduction

The decentralized finance (DeFi) ecosystem has long sought alternatives to fiat-backed tokens, aiming to provide users
with assets that combine dollar-like stability with yield generation. However, existing solutions, particularly
stablecoins, suffer from inherent flaws: they are often centralized, opaque, and yield-free for holders.

USDN aims to solve this problem by operating a fully decentralized structured product.
Its architecture eliminates dependencies on centralized exchanges (CEXs) and custodial intermediaries.
Instead, users interact with smart contracts to mint or redeem USDN tokens, as well as to open long perpetual positions.
The underlying asset deposited to mint USDN tokens is used as liquidity for the structured product to enable leveraged
trading. The first deployment of this protocol uses the @wsteth #cite(<lido-wsteth>) as underlying asset.
This means that we combine the yield of the protocol with that of staking ETH automatically.

= Architecture Overview

The USDN protocol is comprised of two main components: the _vault_ and the _long side_, each having a balance of the
underlying asset. The sum of these balances does not change unless a deposit or withdrawal is made towards the vault
(see @sec:token), a new long position is opened, some protocol fees are taken, or liquidation rewards are given out to
an actor of the protocol. Any change in the long side balance due to a change in the underlying asset price or
#glspl("funding") is compensated by an equal but opposite change in the vault balance.

The vault holds the amount of underlying assets necessary to back the value of the USDN token (see @sec:token_price).
For instance, if the price of the USDN token is \$1 and its total supply is 1000_USDN, and if the price of each
#gls("wsteth") is \$2000, then the vault balance is 0.5_wstETH. Each deposit increases the vault balance an mints new
USDN tokens.

The long side holds the amount of underlying assets corresponding to the summed value of all the long perpetual
positions that exist currently. For example (ignoring fees), a newly open position with an initial collateral of
1_wstETH would increase the long side balance by 1_wstETH, because the position did not lose or gain any value yet,
the asset price being the same as the entry price of the position. If the price of the underlying asset increases, the
value of the position increases (with a leverage effect), and a corresponding decrease in the vault balance occurs
(see @sec:long_pnl).

When the protocol is balanced, the vault balance is exactly equal to the borrowed amount of the long side. To
incentivize this equilibrium, the protocol charges a funding fee to the side with the higher @trading_expo, and
rewards this amount to the other side (see @sec:funding).

= USDN Token <sec:token>

== Overview

The USDN token is a synthetic USD token designed to approximate the value of one US dollar while delivering consistent
returns to its holders. Unlike a stablecoin, USDN does not claim to maintain a rigid peg to \$1. Instead, it oscillates
slightly above or below this reference value, supported by market forces and the protocol's innovative mechanisms.

The value of USDN comes from assets (a specific ERC20 token) stored in the protocol's vault. This can be any token for
which a price oracle is available and for which the balance does not change over time without transfer. For the first
release of the protocol, the token is #gls("wsteth").

== Price <sec:token_price>

Due to the algorithmic nature of the USDN token, its price in dollars $P_"usdn"$ can be calculated using the following
formula:

$ P_"usdn" = frac(B_"vault" P_"asset", S_"tot") $ <eq:usdn_price>

where $B_"vault"$ is the balance of assets held in the protocol's vault, $P_"asset"$ is the price of the asset token in
USD, and $S_"tot"$ is the total supply of USDN tokens.

== Token Minting <sec:token_minting>

USDN tokens are minted whenever a deposit is made into the protocol's vault. The amount of minted USDN $A_"usdn"$ is
calculated by dividing the dollar value of the deposited assets by the USDN price:

$ A_"usdn" = frac(A_"asset" P_"asset", P_"usdn") $ <eq:usdn_minting>

Taking into account @eq:usdn_price, the minting formula can be rewritten as:

$ A_"usdn" = frac(A_"asset" S_"tot", B_"vault") $

== Token Burning <sec:token_burning>

When assets are removed from the protocol's vault, USDN tokens are burned in proportion to the withdrawn amount,
following @eq:usdn_minting. Thus, for a given amount of USDN to be burned, the corresponding withdrawn assets amount is:

$ A_"asset" = frac(A_"usdn" P_"usdn", P_"asset") = frac(A_"usdn" B_"vault", S_"tot") $

== Yield Sources

From @eq:usdn_price, it is clear that the USDN price is influenced by the total assets held in the protocol's vault.
As such, if the vault balance increases as a result of position fees, losses from long positions, or @funding payments,
the USDN price will rise. When a certain threshold is reached, the token #glspl("rebase") to a price slightly above \$1
by increasing the total supply and balance of each holder. This increase in balance represents the yield of the USDN
token. The rebase mechanism ensures that yields do not induce a price that significantly exceeds the value of \$1.
There is no balance and total supply adjustment (rebase) if the price falls below \$1.

= Vault

The vault manages the supply of USDN tokens. The two main actions of the vault are deposits and withdrawals.

The deposit action allows to lock assets into the vault and mint a proportional amount of USDN tokens by providing an
oracle price for the asset token.
It follows the formula described in @sec:token_minting.

The withdrawal action allows to redeem USDN tokens for an equivalent dollar amount of assets from the vault.
It follows the formula described in @sec:token_burning.

= Long Side

== Liquidation

The down side of leveraged long position is they can be liquidated.
The liquidation can occur when the value of the collateral isn't enough to pay back the borrowing part.
The collateral is used to pay back the borrowed part, the owner of the position loose the collateral in this case.
Liquidation of positions is a critical mechanism, if it's executed too late, the position will not have enough collateral to pay back the lend part.
If this happen, the position will accumulate bad dept, which will impact the vault.
To avoid this, liquidation need to be trigger the fastest possible.

To track liquidation, we are using ticks, in a similar implementation of Uniswap V3 @uniswap-v3[p.~5].

We implemented multiple solutions to avoid late liquidation :
- A liquidation penalty, which increase the liquidation price of the position.
- A reward for the sender of the liquidation transaction. The reward isn't principally determined by the collateral remaining in the position but with the gas cost.
$G_"used"$ is the amount of gas spent for the transaction, $N_"liquidatedTicks"$ is the number of ticks liquidated,
$P_"gas"$ the price of the gas determined by taking the lower amount between $2 * "block_base_fee"$ and the gas price of the transaction,
$M_"gas"$ is the gas multiplier, $P_"liquidatedTicks"$ the price of the liquidated tick, $E_"liquidatedTicks"$ the total exposure of the liquidated tick,
$M_"position"$ is the position multiplier

The formula is
$ "ETH_rewards" = (G_"used" + G_"tick" * N_"liquidatedTicks") * P_"gas" * M_"gas" + sum_(i=0)^N_"liquidatedTicks" ((P_"liquidatedTicks"_i - P_"asset") * E_"liquidatedTicks"_i )/ P_"asset" * M_"position" $


== Position Value, Profits and Losses <sec:long_pnl>

= Imbalance

= Funding <sec:funding>

= Glossary

// reset template styles for the figures in the glossary
#show figure: set text(9pt)
#show figure.caption: pad.with(x: -10%)
#print-glossary(glossary)
