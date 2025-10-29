use std::env;

use anyhow::{anyhow, Context, Result};
use diesel::pg::PgConnection;
use diesel::prelude::*;
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

const MIGRATIONS: EmbeddedMigrations = embed_migrations!("../../crates/tycho-storage/migrations");

fn main() -> Result<()> {
    let database_url = env::var("DATABASE_URL")
        .context("DATABASE_URL environment variable must be set for migration-runner")?;

    let mut connection = PgConnection::establish(&database_url)
        .with_context(|| format!("failed to connect to database at {database_url}"))?;

    connection
        .run_pending_migrations(MIGRATIONS)
        .map_err(|err| anyhow!("diesel migrations execution failed: {err}"))?;

    println!("migration-runner: migrations are up to date");

    Ok(())
}
