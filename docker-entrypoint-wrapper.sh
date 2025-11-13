#!/bin/bash
set -e

echo "=== PostgreSQL Cost Guard Extension - Container Startup ==="

# Start SSH server as root
echo "Starting SSH server..."
sudo /usr/sbin/sshd

echo "SSH server started on port 22"
echo ""
echo "=== Delegating to PostgreSQL entrypoint ==="
echo ""

# Execute the standard PostgreSQL docker-entrypoint.sh
# This handles all PostgreSQL initialization, user switching, etc.
exec /usr/local/bin/docker-entrypoint.sh "$@"
