use std::{
    collections::HashMap,
    fs,
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
    text_index::TextRangeExtensions as _,
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

    for entry in WalkDir::new("src") {
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
    let storage_struct_query = Query::parse(
        r#"
        [MemberAccessExpression
            [Expression ["s"]]
            [Period]
            [MemberAccess
                @var_name [Identifier]
            ]
            ...
        ]
        "#,
    )?;
    let normal_storage_query = Query::parse(
        r#"
        @var_name [Identifier]
        "#,
    )?;
    // mapping of function identifier offset to a list of accessed members
    let mut accesses = HashMap::<usize, Vec<String>>::new();
    for m in cursor.query(vec![storage_struct_query, normal_storage_query]) {
        let index = m.query_number;
        let captures = m.captures;
        let cursors = captures.get("var_name").unwrap();
        let cursor = cursors.first().unwrap();
        let mut member_name = cursor.node().unparse();
        if index == 0 {
            member_name = format!("s.{member_name}");
        } else {
            let mut parent_cursor = cursor.clone();
            if parent_cursor.go_to_parent()
                && parent_cursor
                    .node()
                    .is_nonterminal_with_kind(NonterminalKind::MemberAccess)
            {
                continue;
            }
            if parent_cursor.go_to_parent()
                && parent_cursor
                    .node()
                    .is_nonterminal_with_kind(NonterminalKind::FunctionCallExpression)
            {
                continue;
            }
            if !member_name.starts_with('_') {
                continue;
            }
        }

        let mut function_cursor = cursor.clone();
        while function_cursor.go_to_parent() {
            if !function_cursor
                .node()
                .is_nonterminal_with_kind(NonterminalKind::FunctionDefinition)
            {
                continue;
            };
            if function_cursor.go_to_next_terminal_with_kind(TerminalKind::Identifier) {
                let range = function_cursor.text_range();
                let function_accesses = accesses.entry(range.start.utf8).or_default();
                let function_name = function_cursor.node().unparse();
                if function_accesses.contains(&member_name) {
                    eprintln!(
                        "Function `{function_name}` in {}:{} uses `{member_name}` more than once",
                        path.to_string_lossy(),
                        range.line().start,
                    );
                    break;
                }
                function_accesses.push(member_name);
            }
            break;
        }
    }

    Ok(())
}
