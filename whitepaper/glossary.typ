#let glossary = (
  (
    key: "wsteth",
    short: "wstETH",
    long: "Lido wrapped staked ETH",
    description: [
      wstETH is a wrapped version of the tokenized staked ETH from Lido.
    ],
  ),
  (
    key: "trading_expo",
    short: "trading exposure",
    description: [
      The trading exposure of the vault side is equal to the vault balance.
      The trading exposure of the long side is equal to the @total_expo of all long positions, minus the long side
      balance. It represents the borrowed part of all long positions.
    ],
  ),
  (
    key: "total_expo",
    short: "total exposure",
    description: [
      The total exposure of a position is the product of the position's initial collateral and initial leverage.
    ],
  ),
  (
    key: "funding",
    short: "funding fee",
    description: [
      A fee charged to the side with the higher @trading_expo, and rewarded to the other side. The fee is calculated by
      multiplying the funding rate per day by the long side trading exposure, and then normalized to the elapsed
      duration.
    ],
  ),
  (
    key: "rebase",
    short: "rebase",
    description: [
      A rebase is a mechanism that adjusts the total supply of a token to maintain a target price. The rebase factor is
      calculated as the ratio of the current price to the target price. The balance of each holder is adjusted
      proportionally.
    ],
  ),
  (
    key: "liquidation_price",
    short: "liquidation price",
    description: [
      The liquidation price is the threshold at which a position's value becomes too low to sustain. If the market price hits this level, the position can be liquidated to limit further losses.
    ],
  ),
  (
    key: "bad_debt",
    short: "bad debt",
    description: [
      Bad debt is a mechanism in leverage trading, when the borrowed amount is worth more than the value of the collateral. The value will be a loss for the protocol instead of the owner of the position becoming insolvent.
    ],
  ),
)
