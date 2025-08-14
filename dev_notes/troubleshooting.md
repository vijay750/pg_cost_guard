# Troubleshooting Guide - PostgreSQL Cost Guard Extension

## Common Issues and Solutions

### 1. Build Errors

#### Issue: `make: *** No rule to make target '../../../src/Makefile.global'`
**Cause:** Makefile trying to reference PostgreSQL source tree files not available in Docker environment.

**Solution:**
```makefile
# Use PGXS-only Makefile (correct version)
MODULE_big = cost_guard
OBJS = cost_guard.o
EXTENSION = cost_guard
DATA = cost_guard--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

#### Issue: `fatal error: float.h: No such file or directory`
**Cause:** Missing standard C library headers.

**Solution:**
Add to Dockerfile:
```dockerfile
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-15 \
    make \
    gcc \
    libc6-dev
```

Add to C source:
```c
#include <float.h>  // For DBL_MAX constant
```

### 2. Docker Issues

#### Issue: `Cannot connect to the Docker daemon`
**Cause:** Docker daemon not running.

**Solution:**
```bash
# On Mac
open -a Docker

# On Linux
sudo systemctl start docker
```

#### Issue: `initdb: error: cannot be run as root`
**Cause:** PostgreSQL initdb cannot run as root user for security reasons.

**Solution:**
Add to Dockerfile:
```dockerfile
# Create postgres user directories with proper ownership
RUN mkdir -p /var/lib/postgresql/data && \
    chown -R postgres:postgres /var/lib/postgresql && \
    chmod 700 /var/lib/postgresql/data

# Switch to postgres user for running PostgreSQL
USER postgres
```

#### Issue: Container exits with code 1
**Cause:** Various potential issues in test execution.

**Debugging Steps:**
```bash
# Check detailed logs
make -f Makefile.test debug

# Run container interactively
docker run -it --rm --entrypoint /bin/bash cost_guard_test

# Check PostgreSQL logs
tail -f /var/lib/postgresql/data/postgresql.log
```

### 3. Extension Loading Issues

#### Issue: `extension "cost_guard" is not available`
**Cause:** Extension not properly installed or not in PostgreSQL's extension path.

**Debugging:**
```sql
-- Check available extensions
SELECT * FROM pg_available_extensions WHERE name LIKE '%cost%';

-- Check extension files
\! find $(pg_config --sharedir) -name "*cost_guard*"
\! find $(pg_config --pkglibdir) -name "*cost_guard*"
```

**Solution:**
```bash
# Rebuild and reinstall
make clean
make
sudo make install
```

### 4. Test Failures

#### Issue: Tests not blocking expensive queries
**Cause:** Extension not loaded or hook not installed.

**Debugging:**
```sql
-- Check if extension is loaded
SELECT * FROM pg_extension WHERE extname = 'cost_guard';

-- Check configuration
SHOW cost_guard.threshold;
SHOW cost_guard.enabled;

-- Test with simple query
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM large_table;
```

#### Issue: `ERRCODE_STATEMENT_TOO_COMPLEX` not raised
**Cause:** Query cost below threshold or extension disabled.

**Solution:**
```sql
-- Lower threshold for testing
SET cost_guard.threshold = 100;

-- Ensure extension is enabled
SET cost_guard.enabled = true;

-- Try more expensive query
SELECT * FROM large_table ORDER BY random();
```

### 5. Performance Issues

#### Issue: Extension causing significant overhead
**Cause:** Hook being called too frequently or inefficient cost checking.

**Debugging:**
```sql
-- Check query execution time with/without extension
SET cost_guard.enabled = false;
EXPLAIN (ANALYZE, TIMING) SELECT ...;

SET cost_guard.enabled = true;
EXPLAIN (ANALYZE, TIMING) SELECT ...;
```

**Mitigation:**
- Increase threshold to reduce false positives
- Consider disabling for specific sessions
- Monitor PostgreSQL logs for warnings

## Debugging Commands

### Extension Status
```sql
-- Check extension installation
SELECT extname, extversion, extrelocatable 
FROM pg_extension 
WHERE extname = 'cost_guard';

-- Check configuration parameters
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name LIKE 'cost_guard%';
```

### Query Cost Analysis
```sql
-- Get detailed cost breakdown
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING) 
SELECT * FROM your_table WHERE conditions;

-- Check plan without execution
EXPLAIN (COSTS, FORMAT JSON) 
SELECT * FROM your_table WHERE conditions;
```

### Log Analysis
```bash
# PostgreSQL logs
tail -f /var/log/postgresql/postgresql-15-main.log

# Docker container logs
docker logs cost_guard_test_container

# Test output
make -f Makefile.test test 2>&1 | tee test_output.log
```

## Test Environment Setup

### Manual Testing
```bash
# Start interactive container
make -f Makefile.test debug

# Inside container:
su - postgres
psql -d postgres

# Create extension and test
CREATE EXTENSION cost_guard;
SET cost_guard.threshold = 1000;
-- Run test queries
```

### Automated Testing
```bash
# Full test suite
make -f Makefile.test test

# Verbose output
make -f Makefile.test test 2>&1 | tee test_results.log

# Clean environment
make -f Makefile.test clean
```

## Common Error Codes

| Error Code | Description | Solution |
|------------|-------------|----------|
| `54001` | Statement too complex | Expected for blocked queries |
| `42883` | Function does not exist | Extension not loaded |
| `42704` | Configuration parameter not found | Extension not installed |
| `58P01` | Undefined file | Missing extension files |

## Performance Tuning

### Optimal Thresholds
- **Development:** 10,000 - 100,000
- **Testing:** 100,000 - 1,000,000  
- **Production:** 1,000,000 - 10,000,000

### Monitoring
```sql
-- Log expensive queries
SET log_min_duration_statement = 1000;

-- Monitor extension impact
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
WHERE query LIKE '%cost_guard%';
```

## Session-Specific Issues Resolved

### Docker User Permission Fix (August 14, 2025)
**Problem:** Container running as root causing initdb to fail
**Solution:** Added proper user switching in Dockerfile
**Files Modified:** Dockerfile.test, docker_test_runner.sh

### PGXS Build System Fix
**Problem:** Makefile referencing PostgreSQL source tree
**Solution:** Simplified to PGXS-only approach
**Files Modified:** Makefile

### Test Suite Enhancement
**Problem:** Simple test queries without proper error handling
**Solution:** Converted to DO $$ blocks with exception handling
**Files Modified:** run_tests.sql

## Getting Help

1. **Check PostgreSQL logs** for detailed error messages
2. **Run tests in debug mode** for interactive troubleshooting
3. **Verify extension files** are properly installed
4. **Test with simple queries** first, then increase complexity
5. **Check configuration parameters** are set correctly

For additional support, examine the test suite in `run_tests.sql` which covers most common scenarios and edge cases.
