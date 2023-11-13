use alloy_primitives::{FixedBytes, I256};
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
    ExpWad {
        /// e(value) in WAD denomination
        #[arg(allow_hyphen_values = true)]
        value: String,
    },
    LnWad {
        /// ln(value) in WAD denomination
        #[arg(allow_hyphen_values = true)]
        value: String,
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
    }
    Ok(())
}
