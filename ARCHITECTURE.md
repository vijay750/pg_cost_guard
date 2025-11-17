# Docker Architecture

## Overview

The Docker setup uses the **standard PostgreSQL entrypoint** from the official postgres:15 image, with a lightweight wrapper to add SSH functionality. This ensures compatibility with PostgreSQL best practices while adding development conveniences.

## Architecture Diagram

```
Container Startup Flow:
┌─────────────────────────────────────────────────────────────┐
│ 1. docker-entrypoint-wrapper.sh (as root)                  │
│    - Starts SSH server                                      │
│    - Delegates to standard PostgreSQL entrypoint            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. /usr/local/bin/docker-entrypoint.sh (standard postgres) │
│    - Initializes PGDATA (if needed)                         │
│    - Runs scripts in /docker-entrypoint-initdb.d/          │
│    - Switches to postgres user                              │
│    - Starts PostgreSQL server                               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. init-extension.sh (during first initialization)         │
│    - Creates cost_guard extension                           │
│    - Verifies installation                                  │
│    - Prints connection info                                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. PostgreSQL running (standard postgres process)          │
│    - Listens on port 5432                                   │
│    - Extension loaded and ready                             │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Dockerfile.test

**Build-time actions:**
- Installs build dependencies (gcc, make, postgresql-server-dev-15)
- Installs SSH server (openssh-server)
- **Builds and installs the extension** (during image build)
- Copies scripts to appropriate locations
- Configures SSH authentication

**Key design decisions:**
- Extension is built during image build (not runtime)
- Uses standard postgres:15 base image
- Minimal modifications to standard PostgreSQL setup

### 2. docker-entrypoint-wrapper.sh

**Purpose:** Thin wrapper around standard PostgreSQL entrypoint

**Responsibilities:**
- Start SSH server (requires root)
- Delegate to `/usr/local/bin/docker-entrypoint.sh` (standard postgres)

**Why a wrapper?**
- SSH server needs to start before PostgreSQL
- PostgreSQL entrypoint switches to postgres user
- Wrapper runs as root, starts SSH, then hands off to postgres entrypoint

**Code:**
```bash
#!/bin/bash
sudo /usr/sbin/sshd
exec /usr/local/bin/docker-entrypoint.sh "$@"
```

### 3. init-extension.sh

**Purpose:** PostgreSQL initialization script (standard postgres pattern)

**Location:** `/docker-entrypoint-initdb.d/`

**When it runs:**
- Only on first container start (when PGDATA is empty)
- Automatically executed by standard postgres entrypoint
- Runs after database initialization, before server starts accepting connections

**What it does:**
- Creates cost_guard extension
- Verifies installation
- Prints connection information

**Standard Pattern:**
The postgres image automatically runs all `.sh` and `.sql` files in `/docker-entrypoint-initdb.d/` during initialization. This is the recommended way to set up databases and extensions.

### 4. run_tests_in_container.sh

**Purpose:** Execute tests in a running container

**Usage:**
- Called by `make -f Makefile.test run-tests`
- Can be run manually: `docker exec <container> /usr/local/bin/run_tests_in_container.sh`

**Responsibilities:**
- Verify PostgreSQL is running
- Ensure extension is installed
- Execute test suite
- Report results

## Why Use Standard PostgreSQL Entrypoint?

### Benefits

1. **Compatibility:** Works exactly like official postgres image
2. **Reliability:** Battle-tested initialization logic
3. **Features:** Automatic support for:
   - Environment variables (POSTGRES_USER, POSTGRES_PASSWORD, etc.)
   - Init scripts in `/docker-entrypoint-initdb.d/`
   - Proper user switching (root → postgres)
   - Signal handling and graceful shutdown
   - Health checks and readiness

4. **Maintainability:** Updates to postgres image automatically benefit us
5. **Best Practices:** Follows PostgreSQL Docker conventions

### What We Add

- **SSH server** (via wrapper)
- **Extension build** (during image build)
- **Extension initialization** (via init script)
- **Test execution** (separate script)

## File Locations

### In Repository
```
cost_guard_extension/
├── Dockerfile.test                    # Image definition
├── docker-entrypoint-wrapper.sh       # Wrapper entrypoint
├── init-extension.sh                  # PostgreSQL init script
├── run_tests_in_container.sh          # Test execution script
├── Makefile.test                      # Docker workflow
└── [extension source files]
```

### In Container
```
/
├── usr/local/bin/
│   ├── docker-entrypoint.sh           # Standard postgres (from base image)
│   ├── docker-entrypoint-wrapper.sh   # Our wrapper
│   └── run_tests_in_container.sh      # Test script
├── docker-entrypoint-initdb.d/
│   └── init-extension.sh              # Extension init (runs once)
├── extension/
│   └── [extension source files]       # Build artifacts
├── usr/lib/postgresql/15/lib/
│   └── cost_guard.so                  # Compiled extension
└── usr/share/postgresql/15/extension/
    ├── cost_guard.control
    └── cost_guard--1.0.sql
```

## Startup Sequence (Detailed)

### First Start (Empty PGDATA)

1. **Wrapper starts** (as root)
   - Starts SSH server on port 22
   - Calls postgres entrypoint with args

2. **Postgres entrypoint** (standard)
   - Detects empty PGDATA
   - Runs `initdb` to create database cluster
   - Configures authentication (pg_hba.conf)
   - Runs all scripts in `/docker-entrypoint-initdb.d/`:
     - **init-extension.sh** creates cost_guard extension
   - Switches to postgres user
   - Starts PostgreSQL server

3. **Container running**
   - PostgreSQL accepting connections on 5432
   - SSH accepting connections on 22
   - Extension loaded and ready

### Subsequent Starts (Existing PGDATA)

1. **Wrapper starts** (as root)
   - Starts SSH server on port 22
   - Calls postgres entrypoint with args

2. **Postgres entrypoint** (standard)
   - Detects existing PGDATA
   - **Skips** initialization scripts
   - Switches to postgres user
   - Starts PostgreSQL server

3. **Container running**
   - PostgreSQL accepting connections on 5432
   - SSH accepting connections on 22
   - Extension already exists from first start

## Extension Rebuild Workflow

If you modify extension code and need to rebuild:

```bash
# SSH into running container
make -f Makefile.test ssh

# Rebuild extension
cd /extension
make clean && make && make install

# Reconnect to PostgreSQL and reload
psql -U postgres -d postgres
DROP EXTENSION cost_guard;
CREATE EXTENSION cost_guard;
```

## Comparison: Custom vs Standard Entrypoint

### Custom Entrypoint (Old Approach)
```bash
# docker_startup.sh
- Start SSH
- Run initdb manually
- Start postgres manually
- Create extension manually
- Keep running with tail -f
```

**Issues:**
- Reimplements postgres initialization
- May miss edge cases
- Harder to maintain
- Doesn't follow postgres conventions

### Standard Entrypoint (Current Approach)
```bash
# docker-entrypoint-wrapper.sh
- Start SSH
- Delegate to standard postgres entrypoint

# init-extension.sh (in /docker-entrypoint-initdb.d/)
- Create extension (runs automatically)
```

**Benefits:**
- Uses proven postgres initialization
- Follows Docker best practices
- Easier to understand and maintain
- Compatible with postgres ecosystem

## Environment Variables

Standard postgres environment variables work as expected:

- `POSTGRES_USER` - Database superuser (default: postgres)
- `POSTGRES_PASSWORD` - Superuser password
- `POSTGRES_DB` - Default database name
- `PGDATA` - Data directory location

These are all handled by the standard postgres entrypoint.

## Summary

The architecture leverages the **standard PostgreSQL Docker entrypoint** with minimal modifications:

1. **Build time:** Extension is compiled and installed
2. **Wrapper:** Adds SSH server before delegating to postgres
3. **Init script:** Creates extension on first start (standard pattern)
4. **Runtime:** Standard postgres behavior with extension loaded

This design is **simple, maintainable, and follows PostgreSQL best practices**.
