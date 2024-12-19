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
@wsteth is \$2000, then the vault balance is 0.5_wstETH. Each deposit increases the vault balance an mints new
USDN tokens.

The long side holds the amount of underlying assets corresponding to the summed value of all the long perpetual
positions that exist currently. For example (ignoring fees), a newly open position with an initial collateral of
1_wstETH would increase the long side balance by 1_wstETH, because the position did not lose or gain any value yet,
the asset price being the same as the entry price of the position. If the price of the underlying asset increases, the
value of the position increases (with a leverage effect), and a corresponding decrease in the vault balance occurs
(see @sec:long_pnl).

When the protocol is balanced, the vault balance is exactly equal to the borrowed amount of the long side
(@sec:imbalance). To incentivize this equilibrium, the protocol charges a funding fee to the side with the higher
@trading_expo, and rewards this amount to the other side (see @sec:funding).

= USDN Token <sec:token>

== Overview

The USDN token is a synthetic USD token designed to approximate the value of one US dollar while delivering consistent
returns to its holders. Unlike a stablecoin, USDN does not claim to maintain a rigid peg to \$1. Instead, it oscillates
slightly above or below this reference value, supported by market forces and the protocol's innovative mechanisms.

The value of USDN comes from assets (a specific ERC20 token) stored in the protocol's vault. This can be any token for
which a price oracle is available and for which the balance does not change over time without transfer. For the first
release of the protocol, the token is @wsteth.

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

The long side manages user positions. A position is comprised of the collateral (in assets) that the user deposited,
together with a leverage which allows to control a larger position than the collateral. For example, a leverage of
3_times with an initial collateral of 1_wstETH behaves like a position of 3_wstETH. The product of the leverage and the
initial collateral is called @total_expo. When the price of the asset reaches the @liquidation_price for a position, its
value is considered too small for it to continue existing, and it gets closed (in a decentralized way). Any remaining
value goes to the vault pool and forms part of the yield of USDN.
The two primary actions for the long side are opening new positions and closing (partially or entirely) existing
positions.

When opening a new position, the user deposits assets as collateral and indicates their desired liquidation price, which
is used to calculate the position's leverage. The entry price is taken from an oracle.
When closing a position, users withdraw part or the entirety of the current value of their position, including any
profit and loss resulting from the asset's price action.

== Position Value, Profits and Losses <sec:long_pnl>

The value of a long position is determined by the current market price of the asset coupled with its @total_expo and
@liquidation_price. The position value $v(p)$ is calculated as follows:

$ v(p) = frac(T (p-p_"liq"), p) $

where $p$ is the price of the asset (in dollars), $T$ is the total exposure of the position, and $p_"liq"$ is the
liquidation price of the position.

According to this formula, the position's value increases when the asset price rises and decreases when the asset price
falls. The position value is used to calculate the @pnl ($Delta v$) relative to the position's initial
collateral.

To calculate the profit of a position, the initial position value ($p_"entry" = 3000$) is compared with the value of
position at a new market price. The initial value of the position is calculated as:

$ v(p_"entry") = v(3000) = frac(3 (3000-1000), 3000) = 2 $

If price of the asset increases to \$4000:

$ v(4000) = frac(3 (4000-1000), 4000) = 2.25 $
$ Delta v = v(4000) - v(3000) = 0.25 $
The position has a profit of 0.25_asset.

If price of the asset decreases to \$2000:

$ v(2000) = frac(3 (2000-1000), 2000) = 1.5 $
$ Delta v = v(2000) - v(3000) = -0.5 $
The position has a loss of 0.5_asset.

== Liquidation <sec:liquidation>

The risk associated with leveraged trading is that a position can be liquidated.
A liquidation occurs when the value of the collateral is insufficient to repay the borrowed amount (with a margin).
In this situation, any remaining value from the position is credited to the vault, and the owner of the position loses
their collateral.

Liquidations are an essential part of the protocol and should be performed in a timely manner. If a liquidation is
executed too late (when the current asset price is much below the @liquidation_price of the position), the effective
position value is negative and would skew the calculations of the #glspl("funding") for other position owners.
Additionally, a negative position value at the time of its liquidation would affect other parts of the protocol like the
"Dip Accumulator" (not described in this paper) and would make it hard to reward the liquidator without incurring a loss
to the vault's balance.

Note that thanks to the algorithmic nature of the @pnl calculations (see @sec:long_pnl), there is no "bad debt" when a
liquidation occurs too late, because an amount equal and opposite to the negative position value was already credited to
the vault side, and can be used to repay the debt in the long side automatically.

=== Liquidation Rewards

To ensure positions are liquidated as soon as possible, and thus reduce the risk of negative effects on the protocol,
executing liquidations is incentivized with a reward paid out to the liquidator.

The reward is mainly derived from the gas cost of a liquidation transaction. The formula is divided into two parts. The
first component is based on the gas cost and depends on the number $n$ of liquidated transactions (in practice,
transactions are grouped into buckets and liquidated in batches, see TODO):

$ r_"gas" = gamma (g_"common" + n g_"pos") $

where $gamma$ is the gas price (in native tokens per gas unit), $g_"common"$ is the constant part of the gas
units spent in the transaction and $g_"pos"$ is the amount of gas unit spent for processing each position.

The sum $(g_"common" + n g_"pos")$ is roughly equal to the total gas used by the liquidation transaction.

The gas price $gamma$ is the lowest value between the block base fee @eip-1559 (with a fixed margin added to it to
account for an average priority fee) and the effective gas price that the liquidator defined for the transaction.

The second component of the reward formula takes into account the @total_expo of each liquidated position $i$, and the
price difference between their liquidation price and $p$, the effective current price used for the liquidation:

$ r_"value" = sum_(i=1)^n ((P_i - p) T_i ) / p $

where $P_i$ is the liquidation price of the position, $p$ is the asset price at the time of liquidation, and $T_i$ is
the total exposure of the position. As the price difference grows (meaning the remaining position value diminishes),
the incentive grows as well, ensuring the profitability of executing liquidations regardless of the current gas price.

The resulting rewards in native tokens is calculated as follows:

$ r = mu dot.op r_"gas" + nu dot.op r_"value" $

where $mu$ and $nu$ are fixed multipliers that can be adjusted to ensure profitability in most cases.

= Trading Exposure <sec:trading_expo>

The @trading_expo of the vault side is defined as ($B_"vault"$ being the vault balance):

$ E_"vault" = B_"vault" $

The trading exposure of the long side $E_"long"$ is defined as:

$ T_i = c_i l_i $
$ E_i = T_i - v_i $
$ T_"long" = sum_i T_i $
$ B_"long" = sum_i v_i $ <eq:value_balance_invariant>
$ E_"long" = sum_i E_i = T_"long" - B_"long" $

where $T_i$ is the @total_expo of a long position $i$ (defined as the product of its initial collateral $c_i$ and
initial leverage $l_i$), $E_i$ is the trading exposure of a position (defined as its total exposure minus its value
$v_i$), $T_"long"$ is the total exposure of the long side, and $B_"long"$ is the long side balance.
The long side trading exposure can be interpreted as the amount of assets borrowed by the long side position owners.

As the price of the asset increases, $B_"long"$ increases and the trading exposure of the long side decreases.
Inversely, as the price of the asset decreases, $B_"long"$ decreases and the trading exposure of the long side
increases.

= Imbalance <sec:imbalance>

The protocol is at its optimum when it is balanced, which means its imbalance is zero. The imbalance is defined as
the relative difference between the #glspl("trading_expo") of both sides (@sec:trading_expo):

$
  I = cases(
    -frac(E_"vault" - E_"long", E_"long") "if" E_"vault" < E_"long",
    frac(E_"long" - E_"vault", E_"vault") "else",
  )
$ <eq:imbalance>

From @eq:imbalance, we can see that the imbalance is positive when the long side has a larger trading exposure. We can
also see that the imbalance is bounded by $[-1, 1]$.

= Funding <sec:funding>

To incentivize depositors in the protocol side with the lowest @trading_expo, the protocol charges a @funding to the
largest side, which is paid to the smaller side. The fee for a time interval $Delta t$ (in seconds) starting at instant
$t_1$ and ending at $t_2$ is defined as:

$ F_(Delta t) = F_(t_1,t_2) = E_"long"_(t_1) f_(Delta t) $

where $E_"long"_(t_1)$ is the trading exposure of the long side at the beginning of the interval and $f_(Delta t)$ is
the funding rate for that interval.

The funding rate for that interval is calculated as:

$
  f_(Delta t) &= f_(t_1,t_2) \
  &= frac(t_2 - t_1, 86400) (s "sgn"(I_(t_1)) I_(t_1)^2 + sigma_(t_0,t_1))
$ <eq:funding_rate>

where $s$ is a scaling factor that can be tuned, $"sgn"(I)$ is the signum function#footnote[The signum function returns
$-1$ if the sign of its operand is negative, $0$ if its value is zero, and $1$ if it's positive.] applied to the
imbalance $I_(t_1)$ @eq:imbalance at instant $t_1$ and $sigma$ is a skew factor (see @sec:skew).
The denominator of the fraction refers to the number of seconds in a day, which means that $f_(t-86400,t)$ is the daily
funding rate for the period ending at $t$.
It can be observed that the sign of the funding rate matches the sign of the imbalance so long as the $sigma$ term
is zero, thus a positive imbalance (more long trading exposure) results in a positive funding rate in that case.
If the $sigma$ term is largely negative, the funding rate could be negative even if the imbalance is positive.

Note that the funding rate is calculated prior to updating the skew factor (which itself depends on the daily funding
rate), so the skew factor is always the one calculated for the previous time period.

At the end of the funding period $Delta t$, the vault and long side balances are updated as follows (ignoring profits
and losses):

$
  B_"vault"_(t_2) &= B_"vault"_(t_1) + F_(t_1,t_2) \
  B_"long"_(t_2) &= B_"long"_(t_1) - F_(t_1,t_2)
$

== Skew Factor <sec:skew>

In traditional finance, #glspl("funding") are usually positive and serve as a kind of interest rate on the amount
borrowed by the long side. This means that fees should ideally not be zero even if the protocol is perfectly
balanced.

The dynamic skew factor $sigma$ is introduced to ensure that the funding rate matches the market's accepted interest
rate when the protocol is balanced. This factor is calculated as an exponential moving average of the daily funding
rate. For a time interval $Delta t$, the skew factor is updated as follows:

$
  sigma_(Delta t) &= sigma_(t_1,t_2) = alpha f_(t_2-86400,t_2) + (1 - alpha) sigma_(t_0,t_1) \
  &= frac(Delta t, tau) f_(t_2-86400,t_2) + frac(tau - Delta t, tau) sigma_(t_0,t_1)
$

where $alpha$ is the smoothing factor of the moving average, $tau$ is the time constant of the moving average,
$f_(t_2-86400,t_2)$ is the daily funding rate for the last day, and $sigma_(t_0,t_1)$ is the previous value of the skew
factor.

Because this factor is summed with the part of the funding rate which is proportional to the imbalance in
@eq:funding_rate, it shifts the default funding rate value when the protocol is balanced. In practice, if the imbalance
remains positive (more @trading_expo in the long side) for some time, the daily funding rate will keep increasing.
When the funding fees become too important for the long side position owners, they will be incentivized to close their
positions, which will decrease the imbalance.
When the imbalance reaches zero, the daily funding rate will stop increasing, and maintain its current value thanks to
the skew factor. This ensures that the market finds its own daily funding rate which is deemed acceptable by the
protocol actors.

= Glossary

// reset template styles for the figures in the glossary
#show figure: set text(9pt)
#show figure.caption: pad.with(x: -10%)
#print-glossary(glossary)
