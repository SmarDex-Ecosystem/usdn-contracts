use std::ops::DivAssign;

use alloy_primitives::{FixedBytes, I256, U256};
use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use rug::{
    float::Round,
    ops::{DivRounding, MulAssignRound, Pow},
    Float, Integer,
};

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

    let wad: Integer = "1000000000000000000".parse().unwrap();

    match &cli.command {
        Commands::ExpWad { value } => {
            let mut value = Float::with_val(512, Float::parse(value)?);
            value.div_assign(&wad);
            let mut res = value.exp();
            res.mul_assign_round(&wad, Round::Nearest);
            res.floor_mut();
            print_i256_hex(res)?;
        }
        Commands::LnWad { value } => {
            let mut value = Float::with_val(512, Float::parse(value)?);
            value.div_assign(&wad);
            let mut res = value.ln();
            res.mul_assign_round(&wad, Round::Nearest);
            res.round_mut();
            print_i256_hex(res)?;
        }
        Commands::PowWad { base, exp } => {
            let mut base = Float::with_val(512, Float::parse(base)?);
            base.div_assign(&wad);
            let mut exp = Float::with_val(512, Float::parse(exp)?);
            exp.div_assign(&wad);
            let mut res = base.pow(exp);
            res.mul_assign_round(&wad, Round::Nearest);
            res.round_mut();
            print_i256_hex(res)?;
        }
        Commands::DivUp { lhs, rhs } => {
            let lhs: Integer = lhs.parse()?;
            let rhs: Integer = rhs.parse()?;
            let res = lhs.div_ceil(rhs);
            print_u256_hex(res)?;
        }
    }
    Ok(())
}

fn print_i256_hex(x: Float) -> Result<()> {
    let x_wad = x
        .to_integer()
        .ok_or_else(|| anyhow!("can't convert to integer"))?;
    let x_hex: I256 = x_wad.to_string().parse()?;
    let bytes: [u8; 32] = x_hex.to_be_bytes();
    let x_bytes: FixedBytes<32> = bytes.into();
    print!("{x_bytes}");
    Ok(())
}

fn print_u256_hex(x: Integer) -> Result<()> {
    let x_hex: U256 = x.to_string().parse()?;
    let bytes: [u8; 32] = x_hex.to_be_bytes();
    let x_bytes: FixedBytes<32> = bytes.into();
    print!("{x_bytes}");
    Ok(())
}
