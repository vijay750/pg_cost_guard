#!/bin/bash
set -e

# This script runs automatically during PostgreSQL initialization
# It's executed by the standard docker-entrypoint.sh in /docker-entrypoint-initdb.d/

echo "=== Initializing Cost Guard Extension ==="

# Add cost_guard to shared_preload_libraries so it loads at server start
echo "shared_preload_libraries = 'cost_guard'" >> "$PGDATA/postgresql.conf"

# Note: The server will be restarted by docker-entrypoint.sh after init scripts run
echo "Added cost_guard to shared_preload_libraries"

# Create the extension in the default database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS cost_guard;
    
    -- Verify extension was created and library is loaded
    SELECT extname, extversion 
    FROM pg_extension 
    WHERE extname = 'cost_guard';
    
    -- Verify GUC parameters are available
    SHOW cost_guard.threshold;
    SHOW cost_guard.enabled;
EOSQL

echo "✅ Cost Guard extension initialized successfully"
echo ""
echo "=== Container Ready ==="
echo "PostgreSQL is running on port 5432"
echo "SSH server is running on port 22"
echo "  SSH login: ssh -p 2222 postgres@localhost (password: testpass)"
echo "  Root login: ssh -p 2222 root@localhost (password: testpass)"
echo ""
echo "To run tests: make -f Makefile.test run-tests"
echo ""
