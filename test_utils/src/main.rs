use std::{
    ops::DivAssign,
    time::{SystemTime, UNIX_EPOCH},
};

use alloy_primitives::{Bytes, FixedBytes, I256, U256};
use alloy_sol_types::SolValue;
use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use data_streams_report::report::Report;
use hmac::{Hmac, Mac};
use rug::{
    float::Round,
    ops::{DivRounding, MulAssignRound, Pow},
    Float, Integer,
};
use serde::Deserialize;
use sha2::{Digest, Sha256};

#[derive(Deserialize, Debug)]
struct HermesResponse {
    binary: PythBinaryData,
    parsed: Vec<PythParsedData>,
}

#[derive(Deserialize, Debug)]
struct PythBinaryData {
    data: Vec<String>,
}

#[derive(Deserialize, Debug)]
struct PythParsedData {
    price: PythPrice,
}

#[derive(Deserialize, Debug)]
struct PythPrice {
    conf: String,
    price: String,
    expo: i64,
    publish_time: u64,
}

#[derive(Debug, Deserialize)]
pub struct ReportResponse {
    pub report: Report,
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
        #[arg(allow_hyphen_values = true, value_parser = parse_float)]
        value: Float,
    },
    /// ln(x) in WAD denomination
    LnWad {
        /// operand
        #[arg(allow_hyphen_values = true, value_parser = parse_float)]
        value: Float,
    },
    PowWad {
        /// Base
        #[arg(value_parser = parse_float)]
        base: Float,
        /// Exponent
        #[arg(value_parser = parse_float)]
        exp: Float,
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
    CalcMintUsdnShares {
        amount: Integer,
        vault_balance: Integer,
        usdn_total_shares: Integer,
    },
    /// Compare different mint usdn calculation implementations (with vaultBalance equal to zero)
    CalcMintUsdnSharesVaultBalanceZero {
        amount: Integer,
        price: Integer,
        decimals: u32,
        usdn_divisor: Integer,
    },
    /// Get price from chainlink data streams api
    ChainlinkPrice {
        /// The chainlink datastream id
        feed_id: String,
        /// The price timestamp
        timestamp: u128,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let wad: Integer = "1000000000000000000".parse().unwrap();

    match cli.command {
        Commands::ExpWad { value } => {
            let mut value = value;
            value.div_assign(&wad);
            let mut res = value.exp();
            res.mul_assign_round(&wad, Round::Nearest);
            res.floor_mut();
            print_float_i256_hex(res)?;
        }
        Commands::LnWad { value } => {
            let mut value = value;
            value.div_assign(&wad);
            let mut res = value.ln();
            res.mul_assign_round(&wad, Round::Nearest);
            res.round_mut();
            print_float_i256_hex(res)?;
        }
        Commands::PowWad { base, exp } => {
            let mut base = base;
            base.div_assign(&wad);
            let mut exp = exp;
            exp.div_assign(&wad);
            let mut res = base.pow(exp);
            res.mul_assign_round(&wad, Round::Nearest);
            res.round_mut();
            print_float_i256_hex(res)?;
        }
        Commands::DivUp { lhs, rhs } => {
            let res = lhs.div_ceil(rhs);
            print_int_u256_hex(res)?;
        }
        Commands::PythPrice { feed, publish_time } => {
            let mut hermes_api_url = std::env::var("HERMES_RA2_NODE_URL")
                .context("getting HERMES_RA2_NODE_URL env variable")?;
            // add / to the end of the url if it's not there
            if !hermes_api_url.ends_with('/') {
                hermes_api_url.push('/');
            }

            let request_url = format!(
                "{hermes_api_url}v2/updates/price/{publish_time}?ids[]={feed}&encoding=hex&parsed=true"
            );
            let response = ureq::get(&request_url).call()?;
            let price: HermesResponse = response.into_json()?;
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
            print_int_u256_hex(total_mint)?;
        }
        Commands::CalcMintUsdnShares {
            amount,
            vault_balance,
            usdn_total_shares,
        } => {
            let numerator = amount * usdn_total_shares;
            let total_mint = numerator / vault_balance;
            print_int_u256_hex(total_mint)?;
        }
        Commands::CalcMintUsdnSharesVaultBalanceZero {
            amount,
            price,
            decimals,
            usdn_divisor,
        } => {
            let numerator = amount * price;
            let total_mint = numerator / 10u128.pow(decimals);
            let total_mint_shares = total_mint * usdn_divisor;
            print_int_u256_hex(total_mint_shares)?;
        }
        Commands::ChainlinkPrice { feed_id, timestamp } => {
            let chainlink_low_latency_api_key = std::env::var("CHAINLINK_DATA_STREAMS_API_KEY")
                .context("getting CHAINLINK_DATA_STREAMS_API_KEY env variable")?;

            let chainlink_user_secret = std::env::var("CHAINLINK_DATA_STREAMS_API_SECRET")
                .context("getting CHAINLINK_DATA_STREAMS_API_SECRET env variable")?;

            let chainlink_rest_url = std::env::var("CHAINLINK_DATA_STREAMS_API_URL")
                .context("getting CHAINLINK_DATA_STREAMS_API_URL env variable")?;

            let path = format!("/api/v1/reports?feedID={feed_id}&timestamp={timestamp}");
            let request_timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("Error: Timestamp in the past")
                .as_millis();

            let hmac_string = generate_hmac(
                "GET",
                &path,
                b"",
                &chainlink_low_latency_api_key,
                request_timestamp,
                &chainlink_user_secret,
            )?;

            let response = ureq::get(&format!("{chainlink_rest_url}{path}"))
                .set("Authorization", &chainlink_low_latency_api_key)
                .set("X-Authorization-Timestamp", &request_timestamp.to_string())
                .set("X-Authorization-Signature-SHA256", &hmac_string)
                .call()?;

            let report_response: ReportResponse = response.into_json()?;
            let report: Report = report_response.report;

            print!("{}", report.full_report);
        }
    }
    Ok(())
}

fn print_float_i256_hex(x: Float) -> Result<()> {
    let x_wad = x
        .to_integer()
        .ok_or_else(|| anyhow!("can't convert to integer"))?;
    let x_hex: I256 = x_wad.to_string().parse()?;
    let bytes: [u8; 32] = x_hex.to_be_bytes();
    let x_bytes: FixedBytes<32> = bytes.into();
    print!("{x_bytes}");
    Ok(())
}

fn print_int_u256_hex(x: Integer) -> Result<()> {
    let x_hex: U256 = x.to_string().parse()?;
    let bytes: [u8; 32] = x_hex.to_be_bytes();
    let x_bytes: FixedBytes<32> = bytes.into();
    print!("{x_bytes}");
    Ok(())
}

fn print_pyth_response(response: HermesResponse) -> Result<()> {
    let parsed = response
        .parsed
        .first()
        .ok_or_else(|| anyhow!("no parsed price in pyth response"))?;
    let price_hex = parsed.price.price.parse::<U256>()?;
    let conf_hex = parsed.price.conf.parse::<U256>()?;
    let decimals: u64 = parsed.price.expo.abs().try_into()?;
    let decimals_hex = U256::from(decimals);
    // Decode vaa from hex
    let decoded_vaa = const_hex::decode(
        response
            .binary
            .data
            .first()
            .ok_or_else(|| anyhow!("no VAA in pyth response"))?,
    )?;
    let data = (
        price_hex,
        conf_hex,
        decimals_hex,
        U256::from(parsed.price.publish_time),
        &decoded_vaa,
    );
    let bytes = data.abi_encode_params();
    let bytes: Bytes = bytes.into();
    print!("{bytes}");
    Ok(())
}

fn parse_float(s: &str) -> Result<Float, String> {
    Ok(Float::with_val(
        512,
        Float::parse(s).map_err(|e| e.to_string())?,
    ))
}

/// Generates an HMAC-SHA256 signature based on the provided parameters.
///
/// # Arguments
///
/// * `method` - The HTTP method (e.g., "GET", "POST", etc.).
/// * `path` - The API endpoint path (e.g., "/api/v1/feeds", "/api/v1/reports/bulk", etc.).
/// * `body` - The request body as a byte slice.
/// * `client_id` - The client's API key.
/// * `timestamp` - The current timestamp as an `u128`.
/// * `user_secret` - The client's API secret.
///
/// # Returns
///
/// A `Result` containing the hex-encoded HMAC string if successful, or an error.
fn generate_hmac(
    method: &str,
    path: &str,
    body: &[u8],
    client_id: &str,
    timestamp: u128,
    user_secret: &str,
) -> Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(body);
    let server_body_hash = hasher.finalize();
    let server_body_hash_hex = hex::encode(server_body_hash);

    // Create the server body hash string
    let server_body_hash_string =
        format!("{method} {path} {server_body_hash_hex} {client_id} {timestamp}");

    // Compute HMAC-SHA256 of the server body hash string
    let mut mac = Hmac::<Sha256>::new_from_slice(user_secret.as_bytes())?;
    mac.update(server_body_hash_string.as_bytes());
    let signed_message = mac.finalize();
    let signed_message_bytes = signed_message.into_bytes();
    let user_hmac = hex::encode(signed_message_bytes);

    Ok(user_hmac)
}
