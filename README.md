# PostgreSQL Cost Guard Extension

A PostgreSQL extension that uses planner hooks to prevent execution of queries exceeding a configurable cost threshold.

## Project Overview

The Cost Guard Extension is a PostgreSQL extension that intercepts query planning to analyze estimated query costs before execution. It provides administrators with fine-grained control over resource-intensive queries by blocking those that exceed configurable thresholds, helping prevent runaway queries from impacting database performance.

## Key Features

- **Query Cost Interception** - Uses PostgreSQL's `planner_hook` to intercept and analyze query plans
- **Configurable Cost Threshold** - Set maximum allowed query cost via `cost_guard.threshold` GUC parameter
- **Runtime Control** - Enable/disable functionality via `cost_guard.enabled` GUC parameter  
- **Smart Warning System** - Generates warnings for queries approaching threshold (80% of limit)
- **Utility Statement Bypass** - Does not interfere with DDL, VACUUM, ANALYZE, and other utility commands
- **Minimal Performance Impact** - Lightweight hook implementation with negligible overhead
- **Helpful Error Messages** - Provides clear error messages with actual vs threshold costs and optimization hints

## Installation

### Prerequisites

- PostgreSQL 11 or later
- PostgreSQL development headers (`postgresql-server-dev` package)
- Build tools (`make`, `gcc`)

### Building from Source

1. **Clone or download the extension source code**
2. **Build the extension using PGXS:**
   ```bash
   make
   ```
3. **Install the extension:**
   ```bash
   sudo make install
   ```

### Docker-based Testing (Recommended for Development)

```bash
# Run complete test suite in isolated environment
make -f Makefile.test test

# Interactive debugging
make -f Makefile.test debug

# Clean up test environment
make -f Makefile.test clean
```

## Quick Start

### 1. Enable the Extension

Connect to your PostgreSQL database and create the extension:

```sql
-- Create the extension (requires superuser privileges)
CREATE EXTENSION cost_guard;
```

### 2. Configure Cost Threshold

Set the maximum allowed query cost (default is 1,000,000):

```sql
-- Set threshold to 500,000 cost units
SET cost_guard.threshold = 500000;

-- Make it persistent across sessions
ALTER SYSTEM SET cost_guard.threshold = 500000;
SELECT pg_reload_conf();
```

### 3. Enable/Disable the Extension

Control when the extension is active:

```sql
-- Enable cost guard (default)
SET cost_guard.enabled = true;

-- Disable cost guard temporarily
SET cost_guard.enabled = false;

-- Make setting persistent
ALTER SYSTEM SET cost_guard.enabled = true;
SELECT pg_reload_conf();
```

### 4. Test the Extension

```sql
-- Check current configuration
SHOW cost_guard.threshold;
SHOW cost_guard.enabled;

-- Test with a low threshold
SET cost_guard.threshold = 1000;

-- This query might be blocked if it exceeds the threshold
SELECT * FROM large_table ORDER BY random() LIMIT 100;
-- ERROR: query cost 15000.00 exceeds threshold 1000.00
-- HINT: Consider optimizing the query or increasing cost_guard.threshold
```

## Configuration Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cost_guard.threshold` | real | 1000000 | Maximum allowed query cost |
| `cost_guard.enabled` | boolean | true | Enable/disable cost guard |

Both parameters require superuser privileges to modify and can be set at session, database, or system level.

## Usage Examples

### Setting Appropriate Thresholds

```sql
-- Development environment (catch expensive queries early)
SET cost_guard.threshold = 100000;

-- Production environment (allow complex but reasonable queries)
SET cost_guard.threshold = 5000000;

-- Temporarily disable for data migration
SET cost_guard.enabled = false;
-- Run migration scripts
SET cost_guard.enabled = true;
```

### Monitoring Query Costs

```sql
-- Check query cost without executing
EXPLAIN (FORMAT TEXT, COSTS ON) 
SELECT * FROM orders o 
JOIN customers c ON o.customer_id = c.id 
WHERE o.order_date > '2024-01-01';

-- View cost in JSON format for programmatic analysis
EXPLAIN (FORMAT JSON, COSTS ON) 
SELECT * FROM large_table WHERE complex_condition;
```

### Handling Blocked Queries

When a query is blocked, you have several options:

1. **Optimize the query** (add indexes, rewrite conditions)
2. **Increase the threshold** temporarily
3. **Disable cost guard** for specific operations
4. **Break down the query** into smaller parts

## Error Messages

The extension provides helpful error messages:

```
ERROR: query cost 150000.00 exceeds threshold 100000.00
HINT: Consider optimizing the query or increasing cost_guard.threshold
```

Warning messages for queries approaching the threshold:

```
WARNING: expensive query detected: cost 85000.00 (threshold: 100000.00)
```

## Uninstalling

To remove the extension:

```sql
-- Remove the extension
DROP EXTENSION cost_guard;
```

To completely uninstall from the system:

```bash
sudo make uninstall
```

## File Structure

```
cost_guard_extension/
├── README.md                 # This file
├── cost_guard.c              # Main extension source code
├── cost_guard.control        # Extension control file
├── cost_guard--1.0.sql      # Extension installation script
├── Makefile                  # Build configuration (PGXS)
├── run_tests.sql            # Automated test suite
├── Dockerfile.test          # Docker test environment
├── docker_test_runner.sh    # Test execution script
├── docker-compose.test.yml  # Docker Compose configuration
├── Makefile.test           # Docker test automation
└── dev_notes/              # Development documentation
    ├── README.md           # Development overview
    ├── chat_history.md     # Complete development history
    ├── troubleshooting.md  # Debugging guide
    └── session_summary.md  # Session summaries
```

## Development and Testing

For development and testing information, see the [dev_notes](dev_notes/) directory which contains:

- Complete development history and technical details
- Comprehensive troubleshooting guide
- Docker-based testing infrastructure documentation

## License

This extension is provided as-is for educational and development purposes.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the test suite: `make -f Makefile.test test`
5. Submit a pull request

## Support

For issues and questions:

1. Check the [troubleshooting guide](dev_notes/troubleshooting.md)
2. Review the [development documentation](dev_notes/)
3. Examine PostgreSQL logs for detailed error information
