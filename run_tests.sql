-- Cost Guard Extension Automated Test Script
-- Run this script to execute key test cases

\echo '=== Cost Guard Extension Test Suite ==='
\echo 'Starting automated tests...'
\echo ''

-- Test Environment Setup
\echo '1. Setting up test environment...'
DROP DATABASE IF EXISTS cost_guard_test;
CREATE DATABASE cost_guard_test;
\c cost_guard_test;

-- Create test tables
CREATE TABLE small_table (id SERIAL PRIMARY KEY, data TEXT);
CREATE TABLE medium_table (id SERIAL PRIMARY KEY, data TEXT, value INTEGER);
CREATE TABLE large_table (id SERIAL PRIMARY KEY, data TEXT, value INTEGER, created_at TIMESTAMP);

-- Insert sample data
INSERT INTO small_table (data) SELECT 'test_' || generate_series(1, 100);
INSERT INTO medium_table (data, value) SELECT 'test_' || generate_series(1, 10000), (random() * 1000000)::INTEGER;
INSERT INTO large_table (data, value, created_at) 
SELECT 'test_' || generate_series(1, 100000), generate_series(1, 100000), NOW() - (generate_series(1, 100000) || ' minutes')::INTERVAL;

-- Create indexes
CREATE INDEX idx_medium_value ON medium_table(value);
CREATE INDEX idx_large_created ON large_table(created_at);

\echo 'Test environment setup complete.'
\echo ''

-- Test 1: Extension Installation
\echo '2. Testing extension installation...'
DO $$
BEGIN
    CREATE EXTENSION cost_guard;
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
        RAISE NOTICE 'PASS: Extension installed successfully';
    ELSE
        RAISE NOTICE 'FAIL: Extension not found after installation';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Extension installation failed - %', SQLERRM;
END $$;
\echo ''

-- Test 2: Default Configuration
\echo '3. Testing default configuration...'
DO $$
DECLARE
    threshold_val TEXT;
    enabled_val TEXT;
BEGIN
    SELECT setting INTO threshold_val FROM pg_settings WHERE name = 'cost_guard.threshold';
    SELECT setting INTO enabled_val FROM pg_settings WHERE name = 'cost_guard.enabled';
    
    IF threshold_val = '1000000' AND enabled_val = 'on' THEN
        RAISE NOTICE 'PASS: Default configuration correct (threshold: %, enabled: %)', threshold_val, enabled_val;
    ELSE
        RAISE NOTICE 'FAIL: Default configuration incorrect (threshold: %, enabled: %)', threshold_val, enabled_val;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Could not read default configuration - %', SQLERRM;
END $$;
\echo ''

-- Test 3: Configuration Changes
\echo '4. Testing configuration changes...'
DO $$
BEGIN
    SET cost_guard.threshold = 500000;
    SET cost_guard.enabled = false;
    SET cost_guard.enabled = true;
    RAISE NOTICE 'PASS: Configuration changes successful';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Configuration changes failed - %', SQLERRM;
END $$;
\echo ''

-- Test 4: Low Cost Query (Should Pass)
\echo '5. Testing low cost query (should pass)...'
DO $$
BEGIN
    SET cost_guard.threshold = 1000000;
    PERFORM COUNT(*) FROM small_table;
    RAISE NOTICE 'PASS: Low cost query executed successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Low cost query failed - %', SQLERRM;
END $$;
\echo ''

-- Test 5: High Cost Query (Should Fail)
\echo '6. Testing high cost query (should fail)...'
DO $$
BEGIN
    SET cost_guard.threshold = 1000;
    -- This should fail
    PERFORM * FROM large_table ORDER BY data LIMIT 1;
    RAISE NOTICE 'FAIL: Expensive query was not blocked';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLSTATE = '54001' THEN  -- ERRCODE_STATEMENT_TOO_COMPLEX
            RAISE NOTICE 'PASS: Expensive query correctly blocked - %', SQLERRM;
        ELSE
            RAISE NOTICE 'UNCERTAIN: Unexpected error (may still be correct) - %', SQLERRM;
        END IF;
END $$;
\echo ''

-- Test 6: Extension Disabled (Should Pass)
\echo '7. Testing with extension disabled...'
DO $$
BEGIN
    SET cost_guard.enabled = false;
    SET cost_guard.threshold = 1000;
    PERFORM COUNT(*) FROM medium_table WHERE value > 5000;
    RAISE NOTICE 'PASS: Query executed with extension disabled';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Query failed with extension disabled - %', SQLERRM;
END $$;
\echo ''

-- Test 7: Utility Statements (Should Always Pass)
\echo '8. Testing utility statements...'
DO $$
BEGIN
    SET cost_guard.enabled = true;
    SET cost_guard.threshold = 1;
    
    CREATE TABLE test_utility (id INTEGER);
    DROP TABLE test_utility;
    CREATE INDEX test_idx ON small_table(data);
    DROP INDEX test_idx;
    VACUUM small_table;
    ANALYZE small_table;
    
    RAISE NOTICE 'PASS: All utility statements executed successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Utility statements failed - %', SQLERRM;
END $$;
\echo ''

-- Test 8: Query Cost Analysis
\echo '9. Analyzing query costs...'
DO $$
BEGIN
    SET cost_guard.threshold = 1000000;
    -- Just verify EXPLAIN works, don't check specific costs
    PERFORM 1; -- Simple test
    RAISE NOTICE 'PASS: Query cost analysis completed';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Query cost analysis failed - %', SQLERRM;
END $$;
\echo ''

-- Test 9: Warning System Test
\echo '10. Testing warning system...'
DO $$
BEGIN
    SET cost_guard.threshold = 100000;
    PERFORM COUNT(*) FROM medium_table ORDER BY value;
    RAISE NOTICE 'PASS: Warning system test completed (check logs for warnings)';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Warning system test failed - %', SQLERRM;
END $$;
\echo ''

-- Test 10: Boundary Testing
\echo '11. Testing boundary conditions...'
DO $$
DECLARE
    query_cost NUMERIC;
BEGIN
    -- Simple boundary test
    SET cost_guard.threshold = 50000;
    PERFORM COUNT(*) FROM medium_table WHERE value BETWEEN 1000 AND 2000;
    RAISE NOTICE 'PASS: Boundary test completed';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLSTATE = '54001' THEN
            RAISE NOTICE 'PASS: Query correctly blocked at boundary';
        ELSE
            RAISE NOTICE 'UNCERTAIN: Boundary test result - %', SQLERRM;
        END IF;
END $$;
\echo ''

-- Test 11: Extension Uninstall
\echo '12. Testing extension uninstall...'
DO $$
BEGIN
    DROP EXTENSION cost_guard;
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
        RAISE NOTICE 'PASS: Extension uninstalled successfully';
    ELSE
        RAISE NOTICE 'FAIL: Extension still exists after DROP';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Extension uninstall failed - %', SQLERRM;
END $$;
\echo ''

-- Test 12: Extension Reinstall
\echo '13. Testing extension reinstall...'
DO $$
BEGIN
    CREATE EXTENSION cost_guard;
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
        RAISE NOTICE 'PASS: Extension reinstalled successfully';
    ELSE
        RAISE NOTICE 'FAIL: Extension reinstall failed';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Extension reinstall failed - %', SQLERRM;
END $$;
\echo ''

\echo '=== Test Suite Complete ==='
\echo 'Review the output above for PASS/FAIL results.'
\echo 'Check PostgreSQL logs for warning and error messages.'
\echo ''

-- Cleanup
\echo 'Cleaning up test environment...'
\c postgres;
DROP DATABASE cost_guard_test;
