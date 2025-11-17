#!/bin/bash
set -e

echo "=== Running PostgreSQL Cost Guard Extension Tests ==="

# Set PGPASSWORD for psql commands
export PGPASSWORD="$POSTGRES_PASSWORD"

# Check if PostgreSQL is running
if ! pg_isready -h localhost -p 5432 -U "$POSTGRES_USER" > /dev/null 2>&1; then
    echo "❌ PostgreSQL is not running!"
    exit 1
fi

# Verify extension is installed
echo "Verifying extension installation..."
if ! psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM pg_extension WHERE extname = 'cost_guard';" | grep -q cost_guard; then
    echo "⚠️  Extension not installed, creating it..."
    psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS cost_guard;"
fi

# Run the test suite
echo "Running test suite..."
echo ""

if psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /extension/run_tests.sql; then
    echo ""
    echo "=== ✅ ALL TESTS COMPLETED SUCCESSFULLY ==="
    exit 0
else
    echo ""
    echo "=== ❌ TESTS FAILED ==="
    echo ""
    echo "PostgreSQL logs (last 50 lines):"
    tail -n 50 "$PGDATA/postgresql.log" || echo "Could not read PostgreSQL logs"
    exit 1
fi
