# Changelog

All notable changes to the Cost Guard Extension will be documented in this file.

## [Unreleased]

### Added
- **Row-based Query Limiting**: New `cost_guard.max_plan_rows` GUC parameter to limit queries based on estimated row counts
  - Recursively traverses entire query plan tree to find maximum row estimate at any execution step
  - Blocks queries where any plan node exceeds the configured threshold
  - Default value: 0 (disabled)
  - Useful for preventing queries with large intermediate result sets
  
- **Plan Tree Traversal Function**: `find_max_plan_rows()` function that:
  - Recursively examines all nodes in the query plan tree (left and right subtrees)
  - Returns the maximum row estimate found across all execution steps
  - Includes DEBUG1 logging to show row estimates at each plan node
  
- **Enhanced Error Messages**: 
  - Row-based blocking errors with clear hints
  - Error code: SQLSTATE '54001' (statement too complex)
  - Helpful hints suggesting query optimization or threshold adjustment
  
- **Debug Logging**: 
  - Logs row estimates at each plan node when `client_min_messages = DEBUG1`
  - Shows when subtrees have higher row estimates than current node
  - Helps understand query plan structure and row estimate propagation

- **Comprehensive Test Suite**:
  - Tests for low and high row estimate queries
  - Tests for disabled max_plan_rows behavior
  - Tests for combined cost and row limit enforcement
  - Tests for complex multi-step queries:
    - Aggregate queries (GROUP BY, HAVING, COUNT)
    - Join queries (INNER JOIN, LEFT JOIN, CROSS JOIN)
    - Nested subqueries
    - Complex combinations (joins + aggregates)
  - Tests verifying intermediate plan nodes are checked (not just root)

### Changed
- Updated planner hook to check both cost and row thresholds
- Enhanced documentation with max_plan_rows usage examples
- Updated test suites (run_tests.sql and run_selective_tests.sql)

## [1.0.0] - Initial Release

### Added
- Query cost interception using PostgreSQL planner hooks
- `cost_guard.threshold` GUC parameter for maximum query cost
- `cost_guard.enabled` GUC parameter for runtime control
- Warning system for queries approaching threshold (80% of limit)
- Utility statement bypass (DDL, VACUUM, ANALYZE)
- Comprehensive error messages with optimization hints
- Docker-based testing infrastructure
- Automated test suite
- SSH access for debugging
- Persistent container workflow

### Features
- Blocks queries exceeding configurable cost threshold
- Provides helpful error messages with actual vs threshold costs
- Minimal performance impact
- Compatible with PostgreSQL 11+
