# Docker Workflow Guide

This document describes the new Docker-based development and testing workflow for the PostgreSQL Cost Guard Extension.

## Overview

The Docker setup provides a persistent PostgreSQL container with:
- **PostgreSQL 15** with the cost_guard extension pre-built and installed
- **SSH server** for remote access and debugging
- **Persistent container** that stays running for iterative development

## Quick Start

```bash
# 1. Start the container (builds image, starts PostgreSQL + SSH)
make -f Makefile.test start

# 2. Run tests
make -f Makefile.test run-tests

# 3. SSH into the container if needed
make -f Makefile.test ssh

# 4. Stop the container when done
make -f Makefile.test stop
```

## Available Commands

### Main Workflow
- `make -f Makefile.test start` - Build and start the container
- `make -f Makefile.test run-tests` - Run the test suite in the running container
- `make -f Makefile.test test` - Complete workflow (start + run tests)
- `make -f Makefile.test stop` - Stop the container
- `make -f Makefile.test restart` - Restart the container

### Access & Debugging
- `make -f Makefile.test ssh` - SSH into container as postgres user
- `make -f Makefile.test ssh-root` - SSH into container as root
- `make -f Makefile.test shell` - Open bash shell via docker exec
- `make -f Makefile.test status` - Check container status
- `make -f Makefile.test logs` - View container logs
- `make -f Makefile.test pg-logs` - View PostgreSQL logs

### Build & Cleanup
- `make -f Makefile.test build` - Build the Docker image
- `make -f Makefile.test rebuild` - Clean and rebuild from scratch
- `make -f Makefile.test clean` - Remove container and image
- `make -f Makefile.test clean-all` - Remove container, image, and volumes

## Connection Details

### PostgreSQL
- **Host:** localhost
- **Port:** 5432
- **User:** postgres
- **Password:** testpass
- **Database:** postgres

```bash
# Connect from host machine
psql -h localhost -p 5432 -U postgres -d postgres
# Password: testpass
```

### SSH Access
- **Host:** localhost
- **Port:** 2222
- **Users:** postgres or root
- **Password:** testpass (for both users)

```bash
# SSH as postgres user
ssh -p 2222 postgres@localhost

# SSH as root
ssh -p 2222 root@localhost

# Or use make targets
make -f Makefile.test ssh
make -f Makefile.test ssh-root
```

## Development Workflow

### Iterative Development
1. **Start the container once:**
   ```bash
   make -f Makefile.test start
   ```

2. **Make changes to extension code** (cost_guard.c, etc.)

3. **Rebuild and reinstall in the running container:**
   ```bash
   # SSH into the container
   make -f Makefile.test ssh
   
   # Inside container:
   cd /extension
   make clean && make && make install
   
   # Reconnect to PostgreSQL and reload extension
   psql -U postgres -d postgres
   DROP EXTENSION cost_guard;
   CREATE EXTENSION cost_guard;
   ```

4. **Run tests:**
   ```bash
   # From host
   make -f Makefile.test run-tests
   
   # Or from inside container
   /usr/local/bin/run_tests_in_container.sh
   ```

### Manual Testing
```bash
# SSH into container
make -f Makefile.test ssh

# Connect to PostgreSQL
psql -U postgres -d postgres

# Run manual queries
SHOW cost_guard.threshold;
SET cost_guard.threshold = 1000;
SELECT * FROM pg_class ORDER BY random() LIMIT 10;
```

### Debugging
```bash
# View PostgreSQL logs
make -f Makefile.test pg-logs

# View container logs
make -f Makefile.test logs

# Open shell for investigation
make -f Makefile.test shell

# Check extension status
make -f Makefile.test ssh
psql -U postgres -c "SELECT * FROM pg_extension WHERE extname = 'cost_guard';"
```

## Architecture

### Container Startup Process
1. **Wrapper entrypoint** (`docker-entrypoint-wrapper.sh`) starts SSH server
2. **Standard PostgreSQL entrypoint** (`docker-entrypoint.sh`) is called
3. **PostgreSQL** initializes data directory (if needed)
4. **Init script** (`init-extension.sh`) runs during first initialization
5. **Extension** is created automatically via init script
6. **PostgreSQL** starts and keeps running (standard postgres behavior)

### File Locations in Container
- Extension source: `/extension/`
- PostgreSQL data: `/var/lib/postgresql/data/`
- Extension binaries: `/usr/lib/postgresql/15/lib/cost_guard.so`
- Extension SQL: `/usr/share/postgresql/15/extension/cost_guard*`
- Test scripts: `/usr/local/bin/run_tests_in_container.sh`

## Troubleshooting

### Container won't start
```bash
# Check for existing containers
docker ps -a | grep cost_guard

# Remove old container
make -f Makefile.test clean

# Rebuild from scratch
make -f Makefile.test rebuild
make -f Makefile.test start
```

### Extension not found
```bash
# SSH into container
make -f Makefile.test ssh

# Check if extension files exist
ls -la /usr/lib/postgresql/15/lib/cost_guard.so
ls -la /usr/share/postgresql/15/extension/cost_guard*

# Rebuild extension
cd /extension
make clean && make && make install
```

### Tests failing
```bash
# Run tests with full output
make -f Makefile.test run-tests

# Check PostgreSQL logs
make -f Makefile.test pg-logs

# Run tests manually
make -f Makefile.test ssh
psql -U postgres -f /extension/run_tests.sql
```

### SSH connection refused
```bash
# Check container status
make -f Makefile.test status

# Check if SSH is running
make -f Makefile.test shell
sudo service ssh status

# Restart SSH if needed
sudo service ssh restart
```

## Comparison with Old Workflow

### Old Workflow (Ephemeral Containers)
- Container created, ran tests, and destroyed each time
- No SSH access
- Slower iteration cycle
- Harder to debug

### New Workflow (Persistent Container)
- Container stays running
- SSH access for debugging
- Faster iteration
- Can run tests multiple times without rebuilding
- Can manually test and debug

## Tips

1. **Keep container running** during development for faster iteration
2. **Use SSH** for interactive debugging and manual testing
3. **Use `make shell`** for quick access without SSH setup
4. **Check logs** (`make pg-logs`) when tests fail
5. **Rebuild** (`make rebuild`) if you change Dockerfile or build process
6. **Stop container** (`make stop`) when not in use to free resources

## Example Session

```bash
# Start fresh
make -f Makefile.test clean
make -f Makefile.test start

# Run initial tests
make -f Makefile.test run-tests

# Make code changes to cost_guard.c
vim cost_guard.c

# SSH in and rebuild
make -f Makefile.test ssh
cd /extension
make clean && make && make install
psql -U postgres -c "DROP EXTENSION cost_guard; CREATE EXTENSION cost_guard;"
exit

# Run tests again
make -f Makefile.test run-tests

# Debug if needed
make -f Makefile.test ssh
psql -U postgres
SHOW cost_guard.threshold;
-- manual testing...

# Clean up when done
make -f Makefile.test stop
```
