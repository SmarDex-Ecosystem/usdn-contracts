use alloy_primitives::{ruint::aliases::U768, Bytes, FixedBytes, I256, U256, U512};
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
    /// Perform a uint512 full division, yielding a uint512 output
    Div512 {
        /// Numerator bytes
        a: String,
        /// Denominator bytes
        b: String,
    },
    /// Uint512 addition
    HugeIntAdd {
        /// First operand bytes
        a: String,
        /// Second operand bytes
        b: String,
    },
    /// Uint512 subtraction
    HugeIntSub {
        /// First operand bytes
        a: String,
        /// Second operand bytes
        b: String,
    },
    /// Full multiplication of two uint256
    HugeIntMul256 {
        /// First operand as a uint256
        a: U512,
        /// Second operand as a uint256
        b: U512,
    },
    /// Full multiplication of two uint512
    HugeIntMul {
        /// First operand as a uint512
        a: String,
        /// Second operand as a uint512
        b: String,
    },
    /// Division of a uint512 by a uint256
    HugeIntDiv256 {
        /// First operand as a uint512
        a: String,
        /// Second operand as a uint256
        b: U512,
    },
    /// Division of a uint512 by a uint512
    HugeIntDiv {
        /// First operand as a uint512
        a: String,
        /// Second operand as a uint512
        b: String,
    },
    /// Count-left-zeroes of a uint256
    HugeIntClz {
        /// An unsigned 256-bit integer
        x: U256,
    },
    /// Reciprocal `floor((2^512-1) / d) - 2^256`
    HugeIntReciprocal {
        /// A 256-bit unsigned integer at least equal to 2^255
        d: U256,
    },
    /// Reciprocal `floor((2^768-1) / d) - 2^256`
    HugeIntReciprocal2 {
        /// A 512-bit unsigned integer with its high limb at least equal to 2^255
        d: U512,
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
            let price_diff = Integer::from(&start_price - &liq_price);
            let mut total_expo = Float::with_val(512, amount) * start_price / price_diff;
            total_expo.floor_mut();

            print_int_u256_hex(
                total_expo
                    .to_integer()
                    .ok_or_else(|| anyhow!("can't convert to integer"))?,
            )?;
        }
        Commands::Div512 { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let b = U512::from_be_bytes::<64>(const_hex::decode_to_array(b)?);
            let res = a / b;
            let lsb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[32..].try_into()?);
            let msb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[..32].try_into()?);
            print_u512_hex(lsb, msb);
        }
        Commands::HugeIntAdd { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let b = U512::from_be_bytes::<64>(const_hex::decode_to_array(b)?);
            let res = a + b;
            let lsb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[32..].try_into()?);
            let msb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[..32].try_into()?);
            print_u512_hex(lsb, msb);
        }
        Commands::HugeIntSub { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let b = U512::from_be_bytes::<64>(const_hex::decode_to_array(b)?);
            let res = a - b;
            let lsb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[32..].try_into()?);
            let msb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[..32].try_into()?);
            print_u512_hex(lsb, msb);
        }
        Commands::HugeIntMul256 { a, b } => {
            let res = a * b;
            let lsb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[32..].try_into()?);
            let msb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[..32].try_into()?);
            print_u512_hex(lsb, msb);
        }
        Commands::HugeIntMul { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let b = U512::from_be_bytes::<64>(const_hex::decode_to_array(b)?);
            let res = a * b;
            let lsb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[32..].try_into()?);
            let msb = U256::from_be_bytes::<32>(res.to_be_bytes::<64>()[..32].try_into()?);
            print_u512_hex(lsb, msb);
        }
        Commands::HugeIntDiv256 { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let res = a / b;
            assert!(res <= U512::from(U256::MAX));
            let bytes: [u8; 32] = res.to_be_bytes::<64>()[32..].try_into()?;
            let x_bytes: FixedBytes<32> = bytes.into();
            print!("{x_bytes}");
        }
        Commands::HugeIntDiv { a, b } => {
            let a = U512::from_be_bytes::<64>(const_hex::decode_to_array(a)?);
            let b = U512::from_be_bytes::<64>(const_hex::decode_to_array(b)?);
            let res = a / b;
            assert!(res <= U512::from(U256::MAX));
            let bytes: [u8; 32] = res.to_be_bytes::<64>()[32..].try_into()?;
            let x_bytes: FixedBytes<32> = bytes.into();
            print!("{x_bytes}");
        }
        Commands::HugeIntClz { x } => {
            let bytes: [u8; 32] = x.to_be_bytes();
            let clz = bytes.iter().position(|&b| b != 0).map_or(256, |n| {
                let skipped = n * 8;
                let top = bytes[n].leading_zeros() as usize;
                skipped + top
            });
            print_u256_hex(U256::from(clz));
        }
        Commands::HugeIntReciprocal { d } => {
            let res = U512::MAX / U512::from(d) - (U512::from(U256::MAX) + U512::from(1));
            assert!(res <= U512::from(U256::MAX));
            let bytes: [u8; 32] = res.to_be_bytes::<64>()[32..].try_into()?;
            let x_bytes: FixedBytes<32> = bytes.into();
            print!("{x_bytes}");
        }
        Commands::HugeIntReciprocal2 { d } => {
            let res = U768::MAX / U768::from(d) - (U768::from(U256::MAX) + U768::from(1));
            assert!(res <= U768::from(U256::MAX));
            let bytes: [u8; 32] = res.to_be_bytes::<96>()[64..].try_into()?;
            let x_bytes: FixedBytes<32> = bytes.into();
            print!("{x_bytes}");
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

fn print_u256_hex(x: U256) {
    let bytes: [u8; 32] = x.to_be_bytes();
    let x_bytes: FixedBytes<32> = bytes.into();
    print!("{x_bytes}");
}

fn print_u512_hex(lsb: U256, msb: U256) {
    let data = (lsb, msb);
    let bytes = data.abi_encode_params();
    let bytes: Bytes = bytes.into();
    print!("{bytes}");
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

fn parse_float(s: &str) -> Result<Float, String> {
    Ok(Float::with_val(
        512,
        Float::parse(s).map_err(|e| e.to_string())?,
    ))
}
