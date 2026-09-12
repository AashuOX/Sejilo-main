const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

function splitStatements(sql) {
  const lines = sql.split('\n');
  const cleanedLines = lines.map(line => {
    const trimmed = line.trim();
    if (trimmed.startsWith('--')) return '';
    return line;
  });
  const cleanedSql = cleanedLines.join('\n');

  const statements = [];
  let current = '';
  let inSingleQuote = false;
  let inDoubleQuote = false;

  for (let i = 0; i < cleanedSql.length; i++) {
    const char = cleanedSql[i];
    if (char === "'" && !inDoubleQuote) {
      if (inSingleQuote && cleanedSql[i + 1] === "'") {
        current += "''";
        i++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
    } else if (char === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    }

    if (char === ';' && !inSingleQuote && !inDoubleQuote) {
      const stmt = current.trim();
      if (stmt.length > 0) {
        statements.push(stmt);
      }
      current = '';
    } else {
      current += char;
    }
  }

  const remaining = current.trim();
  if (remaining.length > 0) {
    statements.push(remaining);
  }

  return statements;
}

async function main() {
  const migrationsDir = path.join(__dirname, 'prisma', 'migrations');
  const folders = [
    '0_init',
    '20260820152420_search_and_e2ee_device_keys',
    '20260824162921_add_story_reactions',
    '20260824162922_enhance_user_blocking',
    '20260824162923_add_recommendations',
    '20260825100000_add_user_birth_date',
    '20260829120000_add_saved_posts',
    '20260829140000_add_follow_and_message_requests',
  ];

  console.log('Ensuring _prisma_migrations table exists...');
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "_prisma_migrations" (
      "id" VARCHAR(36) PRIMARY KEY NOT NULL,
      "checksum" VARCHAR(64) NOT NULL,
      "finished_at" TIMESTAMPTZ,
      "migration_name" VARCHAR(255) NOT NULL,
      "logs" TEXT,
      "rolled_back_at" TIMESTAMPTZ,
      "started_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
      "applied_steps_count" INTEGER NOT NULL DEFAULT 0
    );
  `);

  // Clean any failed records
  await prisma.$executeRawUnsafe(`
    DELETE FROM "_prisma_migrations" WHERE finished_at IS NULL;
  `);

  for (const folder of folders) {
    const migrationFile = path.join(migrationsDir, folder, 'migration.sql');
    if (!fs.existsSync(migrationFile)) {
      console.log(`Skipping missing migration: ${folder}`);
      continue;
    }

    // Check if already applied
    const existing = await prisma.$queryRawUnsafe(
      `SELECT migration_name FROM "_prisma_migrations" WHERE migration_name = $1 AND finished_at IS NOT NULL`,
      folder
    );

    if (existing && existing.length > 0) {
      console.log(`Migration ${folder} already applied.`);
      continue;
    }

    console.log(`Applying migration: ${folder}...`);
    const sqlContent = fs.readFileSync(migrationFile, 'utf8');
    const checksum = crypto.createHash('sha256').update(sqlContent).digest('hex');
    const id = crypto.randomUUID();

    const startTime = new Date();
    await prisma.$executeRawUnsafe(
      `INSERT INTO "_prisma_migrations" ("id", "checksum", "migration_name", "started_at")
       VALUES ($1, $2, $3, $4)
       ON CONFLICT ("id") DO NOTHING`,
      id, checksum, folder, startTime
    );

    const statements = splitStatements(sqlContent);
    console.log(`  Executing ${statements.length} statements for ${folder}...`);

    try {
      for (let idx = 0; idx < statements.length; idx++) {
        const stmt = statements[idx];
        await prisma.$executeRawUnsafe(stmt);
      }
      const finishTime = new Date();
      await prisma.$executeRawUnsafe(
        `UPDATE "_prisma_migrations" SET finished_at = $1, applied_steps_count = 1 WHERE id = $2`,
        finishTime, id
      );
      console.log(`Successfully applied: ${folder}`);
    } catch (err) {
      console.error(`Error applying ${folder}:`, err.message);
      await prisma.$executeRawUnsafe(
        `UPDATE "_prisma_migrations" SET logs = $1 WHERE id = $2`,
        err.message, id
      );
      throw err;
    }
  }

  const tables = await prisma.$queryRaw`
    SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;
  `;
  console.log('\nAll migrations applied successfully! Tables in Supabase:');
  tables.forEach(t => console.log(' -', t.table_name));
}

main()
  .catch(err => {
    console.error('Migration failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
