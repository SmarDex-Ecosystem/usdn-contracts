use std::ops::DivAssign;
use alloy_primitives::{Bytes, FixedBytes, I256, U256};
use alloy_sol_types::SolValue;
use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use clap::{Parser, Subcommand};
use rug::{
    float::Round,
    ops::{DivRounding, MulAssignRound, Pow},
    Float, Integer,
};
use serde::Deserialize;

#[derive(Deserialize, Debug)]
struct HermesResponse {
    vaa: String,
    price: PythPrice,
}

#[derive(Deserialize, Debug)]
struct PythPrice {
    conf: String,
    price: String,
    expo: i64,
    publish_time: u64,
}
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
    /// Get price feed from Pyth hermes API
    PythPrice {
        /// The bytes32 price feed
        feed: String,
        /// The publish time
        publish_time: u64,
    },
    /// Compare different total expo calculation implementations
    CalcExpo {
        start_price: String,
        liq_price: String,
        amount: String,
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
        Commands::PythPrice { feed, publish_time } => {
            let mut hermes_api_url = std::env::var("HERMES_RA2_NODE_URL")?;
            // add / to the end of the url if it's not there
            if !hermes_api_url.ends_with('/') {
                hermes_api_url.push('/');
            }

            let request_url = format!(
                "{hermes_api_url}get_price_feed?id={feed}&publish_time={publish_time}&binary=true"
            );
            let response = reqwest::blocking::get(request_url)?;
            let price: HermesResponse = response.json()?;
            print_pyth_response(price)?;
        }
        Commands::CalcExpo { start_price, liq_price, amount } => {
            let start_price: Integer = start_price.parse()?;
            let liq_price: Integer = liq_price.parse()?;
            let amount: Integer = amount.parse()?;

            let price_diff = Integer::from(&start_price - &liq_price);
            let mut total_expo = Float::with_val(512, amount) * start_price / price_diff;
            total_expo.floor_mut();
            
            print_u256_hex(total_expo.to_integer().ok_or_else(|| anyhow!("can't convert to integer"))?)?;
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

fn print_pyth_response(response: HermesResponse) -> Result<()> {
    let price_hex = response.price.price.parse::<U256>()?;
    let conf_hex = response.price.conf.parse::<U256>()?;
    let decimals: u64 = response.price.expo.abs().try_into()?;
    let decimals_hex = U256::from(decimals);
    // Decode vaa from base64 to hex
    let decoded_vaa = STANDARD.decode(response.vaa)?;
    let data = (
        price_hex,
        conf_hex,
        decimals_hex,
        U256::from(response.price.publish_time),
        &decoded_vaa,
    );
    let bytes = data.abi_encode_params();
    let bytes: Bytes = bytes.into();
    print!("{bytes}");
    Ok(())
}
