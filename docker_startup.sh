#!/bin/bash
set -e

echo "=== PostgreSQL Cost Guard Extension - Container Startup ==="
echo "Starting SSH server..."
sudo /usr/sbin/sshd

echo "Initializing PostgreSQL..."
# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") --auth-local=trust --auth-host=md5
fi

# Start PostgreSQL
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

# Create the extension in the default database
echo "Creating cost_guard extension..."
if psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS cost_guard;"; then
    echo "✅ Extension created successfully"
else
    echo "❌ Failed to create extension"
    echo "Checking available extensions..."
    psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM pg_available_extensions WHERE name LIKE '%cost%';"
fi

echo ""
echo "=== Container Ready ==="
echo "PostgreSQL is running on port 5432"
echo "SSH server is running on port 22"
echo "  SSH login: ssh -p 2222 postgres@localhost (password: testpass)"
echo "  Root login: ssh -p 2222 root@localhost (password: testpass)"
echo ""
echo "To run tests: docker exec <container> /usr/local/bin/run_tests_in_container.sh"
echo "Or use: make -f Makefile.test run-tests"
echo ""

# Keep container running
tail -f /dev/null
