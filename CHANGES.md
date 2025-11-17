# Docker Infrastructure Changes

## Summary
Updated the Docker testing infrastructure to provide a persistent container with PostgreSQL and SSH access, enabling iterative development and easier debugging.

## Changes Made

### 1. Dockerfile.test
**Changes:**
- Added SSH server installation (`openssh-server`)
- Added `sudo` and `vim` for convenience
- Configured SSH with password authentication
- Added postgres user to sudoers for service management
- Changed entrypoint from test runner to startup script
- Exposed port 22 for SSH access

**New Features:**
- SSH access as postgres or root user
- Persistent container that stays running
- Pre-built and installed extension on startup

### 2. New File: docker-entrypoint-wrapper.sh
**Purpose:** Wrapper entrypoint that starts SSH then delegates to PostgreSQL

**Functionality:**
- Starts SSH server as root
- Delegates to standard PostgreSQL docker-entrypoint.sh
- Preserves all standard PostgreSQL initialization behavior

### 3. New File: init-extension.sh
**Purpose:** PostgreSQL initialization script (runs once on first start)

**Functionality:**
- Automatically executed by PostgreSQL entrypoint
- Creates cost_guard extension
- Verifies extension installation
- Provides connection information

### 4. New File: run_tests_in_container.sh
**Purpose:** Execute tests in a running container

**Functionality:**
- Checks PostgreSQL is running
- Verifies extension is installed
- Runs the test suite
- Shows PostgreSQL logs on failure
- Returns proper exit codes

### 5. Makefile.test (Complete Rewrite)
**New Targets:**

**Main Workflow:**
- `start` - Build and start persistent container
- `run-tests` - Execute tests in running container
- `test` - Complete workflow (start + run tests)
- `stop` - Stop the container
- `restart` - Restart the container

**Access & Debugging:**
- `ssh` - SSH into container as postgres user
- `ssh-root` - SSH into container as root
- `shell` - Open bash shell via docker exec
- `status` - Check container status
- `logs` - View container logs
- `pg-logs` - View PostgreSQL logs

**Build & Cleanup:**
- `build` - Build Docker image
- `rebuild` - Clean and rebuild from scratch
- `clean` - Remove container and image
- `clean-all` - Remove container, image, and volumes

**Configuration:**
- SSH port: 2222 (configurable via SSH_PORT variable)
- PostgreSQL port: 5432
- Container name: cost_guard_test_container
- Image name: cost_guard_test

### 6. New File: DOCKER_WORKFLOW.md
**Purpose:** Comprehensive guide for the new Docker workflow

**Contents:**
- Quick start guide
- All available commands
- Connection details
- Development workflow examples
- Debugging tips
- Troubleshooting guide
- Comparison with old workflow

## Usage Examples

### Quick Start
```bash
# Start container
make -f Makefile.test start

# Run tests
make -f Makefile.test run-tests

# SSH access
make -f Makefile.test ssh
```

### Development Iteration
```bash
# Start once
make -f Makefile.test start

# Make code changes, then rebuild in container
make -f Makefile.test ssh
cd /extension
make clean && make && make install
psql -U postgres -c "DROP EXTENSION cost_guard; CREATE EXTENSION cost_guard;"

# Run tests
make -f Makefile.test run-tests
```

### Debugging
```bash
# Check status
make -f Makefile.test status

# View logs
make -f Makefile.test pg-logs

# Manual testing
make -f Makefile.test ssh
psql -U postgres
```

## Benefits

### Before (Ephemeral Containers)
- Container created and destroyed for each test run
- No SSH access
- Slow iteration cycle
- Limited debugging capabilities
- Had to rebuild for every test

### After (Persistent Container)
- Container stays running
- SSH access for debugging
- Fast iteration (no rebuild needed)
- Can run tests multiple times
- Manual testing and debugging
- Better developer experience

## Migration Notes

### Old Commands Still Work
The `test` target still works but now:
1. Starts a persistent container (if not running)
2. Runs tests in that container

### New Recommended Workflow
1. `make -f Makefile.test start` (once)
2. `make -f Makefile.test run-tests` (multiple times)
3. `make -f Makefile.test ssh` (for debugging)
4. `make -f Makefile.test stop` (when done)

### Breaking Changes
- Old `debug` target removed (use `ssh` or `shell` instead)
- Old `test-only` target removed (can be re-added if needed)
- Container now persists instead of being ephemeral

## Connection Information

### PostgreSQL
- Host: localhost:5432
- User: postgres
- Password: testpass
- Database: postgres

### SSH
- Host: localhost:2222
- Users: postgres or root
- Password: testpass

## Files Modified
1. `Dockerfile.test` - Added SSH, uses standard PostgreSQL entrypoint with wrapper
2. `Makefile.test` - Complete rewrite with new targets

## Files Created
1. `docker-entrypoint-wrapper.sh` - Wrapper that starts SSH and delegates to PostgreSQL
2. `init-extension.sh` - PostgreSQL init script (creates extension on first start)
3. `run_tests_in_container.sh` - Test execution script
4. `DOCKER_WORKFLOW.md` - Comprehensive workflow guide
5. `CHANGES.md` - This file

## Files Deprecated
1. `docker_startup.sh` - Replaced by wrapper + init script approach

## Testing the Changes

```bash
# Clean slate
make -f Makefile.test clean

# Start container
make -f Makefile.test start

# Verify PostgreSQL is running
psql -h localhost -p 5432 -U postgres -c "SELECT version();"

# Verify SSH works
ssh -p 2222 postgres@localhost "whoami"

# Run tests
make -f Makefile.test run-tests

# Check status
make -f Makefile.test status

# Clean up
make -f Makefile.test stop
```

## Future Enhancements

Possible improvements:
1. Add volume mounting for live code updates
2. Add support for multiple PostgreSQL versions
3. Add performance benchmarking targets
4. Add code coverage reporting
5. Add integration with CI/CD pipelines
