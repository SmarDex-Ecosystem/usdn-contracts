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
      The liquidation price of a position is the price at which the position's value is considered too small for it to continue existing. If the price reaches the liquidation price, the position is liquidated in a decentralized way to prevent further losses.
    ],
  ),
)
