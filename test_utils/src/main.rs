use alloy_primitives::I256;
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
        /// lists test values
        #[arg(allow_hyphen_values = true)]
        exp: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let wad: Decimal = "1000000000000000000".parse().unwrap();

    match &cli.command {
        Commands::ExpWad { exp } => {
            let exp: Decimal = exp.parse().map_err(|e: DecimalParseError| anyhow!(e))?;
            let exp_dec = exp / wad;
            let res = exp_dec.exp().ok_or_else(|| anyhow!("exp overflow"))?;
            let res_wad = (res * wad).floor();
            let res_hex: I256 = res_wad.to_string().parse()?;
            if res_hex == I256::ZERO {
                println!("0x0000000000000000000000000000000000000000000000000000000000000000");
            } else {
                println!("{}", res_hex.to_hex_string());
            }
        }
    }
    Ok(())
}
