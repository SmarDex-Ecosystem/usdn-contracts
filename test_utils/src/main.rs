use alloy_primitives::{FixedBytes, I256, U256};
use anyhow::{anyhow, Result};
use clap::{Parser, Subcommand};
use rug::{
    float::Round,
    ops::{DivRounding, MulAssignRound, Pow},
    Assign, Float, Integer, Rational,
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
            let value: Integer = value.parse()?;
            let value_dec: Rational = Rational::from((value, wad.clone()));
            let mut value_float = Float::new(512);
            value_float.assign(value_dec);
            let mut res = value_float.exp();
            res.mul_assign_round(&wad, Round::Nearest);
            res.floor_mut();
            print_i256_hex(res)?;
        }
        Commands::LnWad { value } => {
            let value: Integer = value.parse()?;
            let value_dec: Rational = Rational::from((value, wad.clone()));
            let mut value_float = Float::new(512);
            value_float.assign(value_dec);
            let mut res = value_float.ln();
            res.mul_assign_round(&wad, Round::Nearest);
            res.round_mut();
            print_i256_hex(res)?;
        }
        Commands::PowWad { base, exp } => {
            let base: Integer = base.parse()?;
            let exp: Integer = exp.parse()?;
            let base_dec: Rational = Rational::from((base, wad.clone()));
            let exp_dec: Rational = Rational::from((exp, wad.clone()));
            let mut base_float = Float::new(512);
            let mut exp_float = Float::new(512);
            base_float.assign(base_dec);
            exp_float.assign(exp_dec);
            let mut res = base_float.pow(exp_float);
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
