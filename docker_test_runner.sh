#!/bin/bash
set -e

echo "=== PostgreSQL Cost Guard Extension Docker Test Runner ==="
echo "Starting PostgreSQL server..."

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") --auth-local=trust --auth-host=md5
fi

# Start PostgreSQL in background
echo "Starting PostgreSQL server..."
pg_ctl -D "$PGDATA" -l "$PGDATA/postgresql.log" start

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h localhost -p 5432 -U "$POSTGRES_USER"; do
    echo "PostgreSQL is not ready yet, waiting..."
    sleep 2
done

echo "PostgreSQL is ready!"

# Set PGPASSWORD for psql commands
export PGPASSWORD="$POSTGRES_PASSWORD"

# Verify extension files are installed
echo "Verifying extension installation..."
ls -la $(pg_config --sharedir)/extension/cost_guard* || echo "Extension files not found in expected location"

# Create the extension in the default database
echo "Creating cost_guard extension..."
if psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS cost_guard;"; then
    echo "Extension created successfully"
else
    echo "Failed to create extension, checking available extensions..."
    psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM pg_available_extensions WHERE name LIKE '%cost%';"
    echo "Checking installed files..."
    find $(pg_config --pkglibdir) -name "*cost_guard*" -ls || echo "No cost_guard files found"
    find $(pg_config --sharedir) -name "*cost_guard*" -ls || echo "No cost_guard files found"
    exit 1
fi

# Run the test suite
echo "Running test suite..."
if psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /extension/run_tests.sql; then
    TEST_EXIT_CODE=0
    echo "Test suite completed successfully"
else
    TEST_EXIT_CODE=1
    echo "Test suite failed"
fi

# Show PostgreSQL logs for debugging
echo ""
echo "=== PostgreSQL Logs ==="
tail -n 50 "$PGDATA/postgresql.log" || echo "Could not read PostgreSQL logs"

# Stop PostgreSQL
echo ""
echo "Stopping PostgreSQL server..."
pg_ctl -D "$PGDATA" stop

# Exit with the test result
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== ALL TESTS COMPLETED SUCCESSFULLY ==="
    exit 0
else
    echo ""
    echo "=== TESTS FAILED ==="
    exit 1
fi
