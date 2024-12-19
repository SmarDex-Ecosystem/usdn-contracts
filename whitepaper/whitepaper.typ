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

== Liquidation <sec:liquidation>

== Position Value, Profits and Losses <sec:long_pnl>

The value of a long position is determined by the current market price of the asset coupled with its @total_expo and
@liquidation_price. The position value $v(p)$ is calculated as follows:

$ v(p) = frac(T (p-p_"liq"), p) $ <eq:pos_value>

where $p$ is the price of the asset (in dollars), $T$ is the total exposure of the position, and $p_"liq"$ is the
liquidation price of the position.

According to this formula, the position's value increases when the asset price rises and decreases when the asset price
falls. The position value is used to calculate profits or losses ($Delta v$) relative to the position's initial
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

= Trading Exposure <sec:trading_expo>

The @trading_expo of the vault side is defined as ($B_"vault"$ being the vault balance):

$ E_"vault" = B_"vault" $

The trading exposure of the long side $E_"long"$ is defined as:

$ T_i = c_i l_i $
$ E_i = T_i - v_i $
$ T_"long" = sum_i T_i $ <eq:total_expo>
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

= Liquidation Ticks

As previously stated in @sec:liquidation, the long side positions are grouped by @liquidation_price into buckets for
efficient liquidation. Each bucket is called a liquidation tick and is identified by its number, ranging from
-322_378 to 980_000.

The tick number of a bucket containing positions can be used to calculate the price at which those positions can be
liquidated, and this price includes a penalty, such that the position value is greater than zero when it can be first
liquidated (see @sec:liquidation). This penalty $psi_i$ denominated in number of ticks, is stored in the bucket's
metadata and allows to calculate the _theoretical_ liquidation price (price at which the position value is zero) of a
position in tick $i$ by retrieving the price of the tick number $(i - psi_i)$.

For instance, if the penalty for tick 1000 is 100_ticks (\~1.05%), the liquidation price of a position in tick 1000 is
the price of tick 900.

== Tick Spacing <sec:tick_spacing>

To improve gas performance when iterating over the ticks, we only consider ticks that are multiples of a tick spacing
$lambda$ for the liquidation buckets. The range of valid ticks is:

#math.equation(block: true, numbering: none)[
  $R => { lambda k | k in ZZ: lr(ceil.l frac(-322378, lambda) ceil.r) <= k <= lr(floor.l frac(980000, lambda) floor.r) }$
]

For the Ethereum implementation, the tick spacing is defined as 100 ticks.

== Unadjusted Price

At the core of the tick system is the equation that dictates the conversion from a tick number to a price that we
qualify as "unadjusted". This equation is:

$ phi_i = 1.0001^i $ <eq:unadjusted_price>

where $phi_i$ is the unadjusted price for the tick $i$. From this formula, we can see that the unadjusted price
increases by 0.01% for each tick. This allow to represent a wide range of prices with a small number of ticks. In
practice, because of the tick number range described above, prices ranging from \$0.000_000_000_000_01 to
\~\$3_tredecillion ($~3.62 times 10^42$) can be represented.

== Adjusted Price

However, because of the @funding mechanism, the liquidation price of a position can change over time. If the funding
fee is positive, a position's collateral is slowly eaten away, which in turn increases its liquidation price. The
"adjusted" price $P_i$ of a tick is thus calculated as:

$ P_i = M phi_i $ <eq:adjusted_price>

where $M$ is a multiplier that represents the accumulated effect of the funding fees. Interestingly, all ticks are
affected by the funding fees in the same way, which means that the multiplier $M$ is the same for all ticks
(see @sec:multiplier_proof).

Since it would be imprecise to represent the multiplier $M$ as a fixed-precision number in the implementation, we derive
an accumulator $A$ from the equations below.

The value of a tick $i$ can be derived from @eq:pos_value:

$ v_i = frac(T_i, l_i) = frac(T_i (p - P_(i - psi_i)), p) $

where $T_i$ is the @total_expo of the positions in the tick, $l_i$ is the effective leverage of the positions in the
tick (at the current price), $p$ is the current price of the asset and $P_(i-psi_i)$ is
the theoretical liquidation price of the positions in this tick ($psi_i$ being the penalty of the tick).
By using @eq:adjusted_price, we can rewrite this equation as:

$ v_i = frac(T_i (p - P_(i - psi_i)), p) = frac(T_i (p - M phi_(i - psi_i)), p) $ <eq:tick_value_mul>

The range of valid ticks $R$ defined in @sec:tick_spacing, we define the following invariant (analog to
@eq:value_balance_invariant for the ticks):

$ B_"long" = sum_(i in R) v_i $ <eq:balance_tick_invariant>

which means that the balance of the long side must be equal to the sum of the value of each tick $i$. We can now combine
@eq:total_expo, @eq:tick_value_mul and @eq:balance_tick_invariant, then solve for $M$:

$
  M = frac(p (sum_(i in R) T_i - B_"long"), sum_(i in R) (T_i phi_(i-psi_i))) = frac(p (T_"long" - B_"long"), A)
$ <eq:liq_multiplier>

$ A = sum_(i in R) (T_i phi_(i-psi_i)) $ <eq:accumulator>

where $A$ is an accumulator that can easily be updated when a position is added or removed from the long side.

Finally, the adjusted price of a tick $P_i$ can be calculated as:

$ P_i = M phi_i = frac(phi_i p (T_"long" - B_"long"), A) $ <eq:adjusted_price_acc>

=== Multiplier Proof <sec:multiplier_proof>

As proof that multiplier $M$ is the same for all ticks, consider a position with a current value $v_0$ and a liquidation
price $phi$ that was not subject to funding fees. The liquidation price for a current asset price $p$ is derived from
@eq:pos_value:

$ phi = p_"liq" (p) = frac(p (T - v_0), T) $

where $T$ is the @total_expo of the position. If the funding rate is $f$, the funding fee for the position is:

$ F = f E = f (T - v_0) $

where $E$ is the @trading_expo of the position.
The new position value $v_1$ is then:

$
  v_1 &= v_0 - F = v_0 - f (T - v_0)\
  &= v_0 (1 + f) - f T
$

The new adjusted liquidation price $P$ is thus:

$
  P &= frac(p (T - v_1), T) = frac(p (T - v_0 (1 + f) + f T), T)\
  &= frac(p (T (1 + f) - v_0 (1 + f)), T)\
  &= (1 + f) frac(p (T - v_0), T) = (1 + f) phi = M phi & qed
$

From this result, we can see that all ticks are affected the funding rate in the same way.

= Glossary

// reset template styles for the figures in the glossary
#show figure: set text(9pt)
#show figure.caption: pad.with(x: -10%)
#print-glossary(glossary)
