use std::{
    collections::HashMap,
    fs::{self, File},
    io::Write as _,
    path::{Path, PathBuf},
    thread::available_parallelism,
};

use anyhow::{bail, Result};
use async_channel::Receiver;
use serde::Deserialize;
use slang_solidity::{
    kinds::{NonterminalKind, TerminalKind},
    language::Language,
    query::Query,
};
use walkdir::WalkDir;

#[derive(Debug, Deserialize)]
struct FoundryProfile {
    solc_version: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FoundryProfiles {
    default: Option<FoundryProfile>,
}

#[derive(Debug, Deserialize)]
struct FoundryConfig {
    profile: Option<FoundryProfiles>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let mut solidity_version = "0.8.26".to_string();
    let config_file = PathBuf::from("foundry.toml");
    if fs::metadata(&config_file).is_ok() {
        let contents = fs::read_to_string(&config_file)?;
        let foundry_config: FoundryConfig = toml::from_str(&contents)?;
        if let Some(solc_version) = foundry_config
            .profile
            .and_then(|p| p.default)
            .and_then(|d| d.solc_version)
        {
            solidity_version = solc_version;
        }
    }
    println!("{solidity_version}");

    let n_threads = available_parallelism()?.get();
    println!("using {n_threads} threads");

    let (tx, rx) = async_channel::unbounded();

    let handles: Vec<_> = (0..n_threads)
        .map(|_| {
            tokio::spawn({
                let rx = rx.clone();
                let solidity_version = solidity_version.clone();
                async move {
                    worker(rx, solidity_version).await?;
                    Ok::<(), anyhow::Error>(())
                }
            })
        })
        .collect();

    for entry in WalkDir::new("src/UsdnProtocol/libraries") {
        let entry = match entry {
            Err(e) => {
                eprintln!("walkdir error: {e:?}");
                continue;
            }
            Ok(entry) => entry,
        };
        let metadata = match entry.metadata() {
            Err(e) => {
                eprintln!("file metadata error: {e:?}");
                continue;
            }
            Ok(metadata) => metadata,
        };
        if metadata.is_dir() {
            continue;
        }
        let path = entry.path();
        match path.extension() {
            Some(ext) if ext == "sol" => {}
            _ => continue,
        }
        tx.send(PathBuf::from(path)).await?;
    }
    tx.close();

    let mut results = Vec::with_capacity(handles.len());
    for handle in handles {
        results.push(handle.await??);
    }

    Ok(())
}

async fn worker(rx: Receiver<PathBuf>, solidity_version: String) -> Result<()> {
    let language = Language::new(solidity_version.parse()?)?;
    while let Ok(path) = rx.recv().await {
        println!("processing {path:?}");
        match parse_and_lint(&language, &path) {
            Ok(()) => {}
            Err(e) => {
                eprintln!("Error parsing {path:?}: {e:?}");
                continue;
            }
        };
    }
    println!("worker exited");
    Ok(())
}

fn parse_and_lint(lang: &Language, path: impl AsRef<Path>) -> Result<()> {
    let path = path.as_ref();
    let contents = fs::read_to_string(path)?;
    let parse_output = lang.parse(NonterminalKind::SourceUnit, &contents);
    for error in parse_output.errors() {
        eprintln!(
            "Error at byte offset {offset}: {message}",
            offset = error.text_range().start.utf8,
            message = error.message()
        );
    }
    if !parse_output.is_valid() {
        bail!("Parse error(s) found in {path:?}")
    }
    let cursor = parse_output.create_tree_cursor();
    let query = Query::parse(
        r#"
        [MemberAccessExpression
            [Expression ["s"]]
            [Period]
            [MemberAccess
                @member_name [Identifier]
            ]
            ...
        ]
        "#,
    )?;
    // mapping of function identifier offset to a list of accessed members
    let mut accesses = HashMap::<usize, Vec<String>>::new();
    for m in cursor.query(vec![query]) {
        let captures = m.captures;
        let cursors = captures.get("member_name").unwrap();
        let cursor = cursors.first().unwrap();
        let member_name = cursor.node().unparse();
        let mut function_cursor = cursor.clone();
        while function_cursor.go_to_parent() {
            let Some(_) = function_cursor
                .node()
                .as_nonterminal_with_kind(NonterminalKind::FunctionDefinition)
            else {
                continue;
            };
            if function_cursor.go_to_next_terminal_with_kind(TerminalKind::Identifier) {
                let offset = function_cursor.text_range().start.utf8;
                let function_accesses = accesses.entry(offset).or_default();
                let function_name = function_cursor.node().unparse();
                if function_accesses.contains(&member_name) {
                    bail!(
                        "Function {function_name} in {:?} uses `s.{member_name}` more than once",
                        path
                    );
                }
                function_accesses.push(member_name);
            }
            break;
        }
    }

    Ok(())
}
