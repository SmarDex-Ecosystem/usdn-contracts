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
    key: "tradingexpo",
    short: "trading exposure",
    description: [
      The trading exposure of the vault side is equal to the vault balance.
      The trading exposure of the long side is equal to the @totalexpo of all long positions, minus the long side
      balance.
    ],
  ),
  (
    key: "totalexpo",
    short: "total exposure",
    description: [
      The total exposure of a position is the product of the position's initial collateral and initial leverage.
    ],
  ),
  (
    key: "funding",
    short: "funding fee",
    description: [
      A fee charged to the side with the higher @tradingexpo, and rewarded to the other side. The fee is calculated by
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
)