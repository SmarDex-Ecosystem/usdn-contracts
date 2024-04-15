use alloy_primitives::{Bytes, FixedBytes, I256, U256};
use alloy_sol_types::SolValue;
use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use clap::{Parser, Subcommand};
use rug::{
    float::Round,
    ops::{DivRounding, MulAssignRound, Pow},
    Complete, Float, Integer,
};
use serde::Deserialize;
use std::ops::DivAssign;

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
        lhs: Integer,
        /// RHS
        rhs: Integer,
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
        start_price: Integer,
        liq_price: Integer,
        amount: Integer,
    },
    /// Compare different mint usdn calculation implementations
    CalcMintUsdn {
        amount: Integer,
        vault_balance: Integer,
        usdn_total_supply: Integer,
    },
    /// Compare different mint usdn calculation implementations (with vaultBalance equal to zero)
    CalcMintUsdnVaultBalanceZero {
        amount: Integer,
        price: Integer,
        decimals: u32,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let wad: Integer = "1000000000000000000".parse().unwrap();

    match cli.command {
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
        Commands::CalcExpo {
            start_price,
            liq_price,
            amount,
        } => {
            let price_diff = &start_price - liq_price;
            let numerator = amount * start_price;
            let total_mint = numerator / price_diff;
            print_u256_hex(total_mint)?;
        }
        Commands::CalcMintUsdn {
            amount,
            vault_balance,
            usdn_total_supply,
        } => {
            let numerator = amount * usdn_total_supply;
            let total_mint = numerator / vault_balance;
            print_u256_hex(total_mint)?;
        }
        Commands::CalcMintUsdnVaultBalanceZero {
            amount,
            price,
            decimals,
        } => {
            let numerator = amount * price;
            let total_mint = numerator / 10u128.pow(decimals);
            print_u256_hex(total_mint)?;
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
