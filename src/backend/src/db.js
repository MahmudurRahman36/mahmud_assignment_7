const { Pool } = require('pg');

// PostgreSQL connection pool configuration
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// Handle pool errors
pool.on('error', (err) => {
  console.error('Unexpected error on idle PostgreSQL client:', err);
  process.exit(-1);
});

// ---------------------------------------------------------------------------
// Auto-migration: create schema if it does not exist yet.
// This runs on every server startup and is fully idempotent (IF NOT EXISTS).
// It removes the hard dependency on the CI/CD psql migration step.
// ---------------------------------------------------------------------------
const initDatabase = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS measurements (
        id               SERIAL PRIMARY KEY,
        weight_kg        NUMERIC(5,2)  NOT NULL CHECK (weight_kg > 0 AND weight_kg < 1000),
        height_cm        NUMERIC(5,2)  NOT NULL CHECK (height_cm > 0 AND height_cm < 300),
        age              INTEGER       NOT NULL CHECK (age > 0 AND age < 150),
        sex              VARCHAR(10)   NOT NULL CHECK (sex IN ('male', 'female')),
        activity_level   VARCHAR(30)   CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'very_active')),
        bmi              NUMERIC(4,1)  NOT NULL,
        bmi_category     VARCHAR(30),
        bmr              INTEGER,
        daily_calories   INTEGER,
        measurement_date DATE          NOT NULL DEFAULT CURRENT_DATE,
        created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
      )
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_measurements_measurement_date
        ON measurements(measurement_date DESC)
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_measurements_created_at
        ON measurements(created_at DESC)
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_measurements_bmi
        ON measurements(bmi)
    `);

    console.log('✅ Database schema initialized (measurements table ready)');

    // Log existing tables for confirmation
    const { rows } = await pool.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"
    );
    console.log('📊 Public schema tables:', rows.map(r => r.table_name));
  } catch (err) {
    console.error('❌ Database initialization error:', err.message);
    process.exit(1);
  }
};

// Test connection then run auto-migration
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection failed:', err.message);
    process.exit(1);
  }
  console.log('✅ Database connected successfully at:', res.rows[0].now);
  initDatabase();
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};