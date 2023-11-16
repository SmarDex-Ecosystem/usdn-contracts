use alloy_primitives::{FixedBytes, I256, U256};
use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use decimal_rs::{Decimal, DecimalParseError};

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// e^x in WAD denomination
    ExpWad {
        /// exponent
        #[arg(allow_hyphen_values = true)]
        value: String,
    },
    /// ln(x) in WAD denomination
    LnWad {
        /// operand
        #[arg(allow_hyphen_values = true)]
        value: String,
    },
    PowWad {
        /// Base
        base: String,
        /// Exponent
        exp: String,
    },
    /// ceil(lhs / rhs)
    DivUp {
        /// LHS
        lhs: String,
        /// RHS
        rhs: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let wad: Decimal = "1000000000000000000".parse().unwrap();

    match &cli.command {
        Commands::ExpWad { value } => {
            let value: Decimal = value.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let value_dec = value / wad;
            let res = value_dec.exp().ok_or_else(|| anyhow!("exp overflow"))?;
            let res_wad = (res * wad).floor();
            let res_hex: I256 = res_wad.to_string().parse()?;
            let bytes: [u8; 32] = res_hex.to_be_bytes();
            let res_bytes: FixedBytes<32> = bytes.into();
            println!("{res_bytes}");
        }
        Commands::LnWad { value } => {
            let value: Decimal = value.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let value_dec = value / wad;
            let res = value_dec.ln().ok_or_else(|| anyhow!("exp overflow"))?;
            let res_wad = (res * wad).round(0);
            let res_hex: I256 = res_wad.to_string().parse()?;
            let bytes: [u8; 32] = res_hex.to_be_bytes();
            let res_bytes: FixedBytes<32> = bytes.into();
            println!("{res_bytes}");
        }
        Commands::PowWad { base, exp } => {
            let base: Decimal = base.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let exp: Decimal = exp.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let base_dec = base / wad;
            let exp_dec = exp / wad;
            let res = base_dec
                .checked_pow(&exp_dec)
                .ok_or_else(|| anyhow!("exp overflow"))?;
            let res_wad = (res * wad).round(0);
            let res_hex: I256 = res_wad.to_string().parse()?;
            let bytes: [u8; 32] = res_hex.to_be_bytes();
            let res_bytes: FixedBytes<32> = bytes.into();
            println!("{res_bytes}");
        }
        Commands::DivUp { lhs, rhs } => {
            let lhs: Decimal = lhs.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let rhs: Decimal = rhs.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let res = (lhs / rhs).ceil();
            let res_hex: U256 = res.to_string().parse()?;
            let bytes: [u8; 32] = res_hex.to_be_bytes();
            let res_bytes: FixedBytes<32> = bytes.into();
            println!("{res_bytes}");
        }
    }
    Ok(())
}
