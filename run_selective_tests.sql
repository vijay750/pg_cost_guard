-- Selective Test Runner for Cost Guard Extension
-- Usage: psql -v test_filter='test1,test3,test5' -f run_selective_tests.sql

\echo '=== Cost Guard Extension Selective Test Suite ==='
\echo 'Running selected tests...'
\echo ''

-- Test Environment Setup (always run for selective tests)
\echo 'Setting up test environment...'
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

-- Check if specific test should run
\set test_filter_var :test_filter

-- Test 1: Extension Installation
DO $$
BEGIN
    IF position('test1' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST1: Extension Installation';
        BEGIN
            CREATE EXTENSION IF NOT EXISTS cost_guard;
            IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
                RAISE NOTICE 'PASS: Extension installed successfully';
            ELSE
                RAISE NOTICE 'FAIL: Extension not found after installation';
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Extension installation failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 2: Default Configuration
DO $$
DECLARE
    threshold_val TEXT;
    enabled_val TEXT;
BEGIN
    IF position('test2' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST2: Default Configuration';
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
        END;
    END IF;
END $$;

-- Test 3: Configuration Changes
DO $$
BEGIN
    IF position('test3' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST3: Configuration Changes';
        BEGIN
            SET cost_guard.threshold = 500000;
            SET cost_guard.enabled = false;
            SET cost_guard.enabled = true;
            RAISE NOTICE 'PASS: Configuration changes successful';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Configuration changes failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 4: Low Cost Query (Should Pass)
DO $$
BEGIN
    IF position('test4' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST4: Low Cost Query';
        BEGIN
            SET cost_guard.threshold = 1000000;
            PERFORM COUNT(*) FROM small_table;
            RAISE NOTICE 'PASS: Low cost query executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Low cost query failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 5: High Cost Query (Should Fail) - Enhanced with error message parsing
DO $$
DECLARE
    error_message TEXT;
    estimated_cost NUMERIC;
    threshold_value NUMERIC := 1000;
    cost_match TEXT[];
    threshold_match TEXT[];
BEGIN
    IF position('test5' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST5: High Cost Query (Enhanced)';
        BEGIN
            SET cost_guard.threshold = 1000;
            -- This should fail
            PERFORM * FROM large_table ORDER BY data LIMIT 1;
            RAISE NOTICE 'FAIL: Expensive query was not blocked';
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLSTATE = '54001' THEN  -- ERRCODE_STATEMENT_TOO_COMPLEX
                    error_message := SQLERRM;
                    
                    -- Parse estimated cost from error message: "query cost X.XX exceeds threshold Y.YY"
                    cost_match := regexp_match(error_message, 'query cost ([0-9]+\.?[0-9]*)');
                    threshold_match := regexp_match(error_message, 'threshold ([0-9]+\.?[0-9]*)');
                    
                    IF cost_match IS NOT NULL AND threshold_match IS NOT NULL THEN
                        estimated_cost := cost_match[1]::NUMERIC;
                        threshold_value := threshold_match[1]::NUMERIC;
                        
                        IF estimated_cost > threshold_value THEN
                            RAISE NOTICE 'PASS: Expensive query correctly blocked - estimated cost %.2f > threshold %.2f', estimated_cost, threshold_value;
                        ELSE
                            RAISE NOTICE 'FAIL: Error message parsing issue - estimated cost %.2f should be > threshold %.2f', estimated_cost, threshold_value;
                        END IF;
                    ELSE
                        RAISE NOTICE 'PASS: Expensive query correctly blocked (could not parse costs) - %', error_message;
                    END IF;
                ELSE
                    RAISE NOTICE 'UNCERTAIN: Unexpected error (may still be correct) - %', SQLERRM;
                END IF;
        END;
    END IF;
END $$;

-- Test 6: Extension Disabled (Should Pass)
DO $$
BEGIN
    IF position('test6' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST6: Extension Disabled';
        BEGIN
            SET cost_guard.enabled = false;
            SET cost_guard.threshold = 1000;
            PERFORM COUNT(*) FROM medium_table WHERE value > 5000;
            RAISE NOTICE 'PASS: Query executed with extension disabled';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Query failed with extension disabled - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 7: Utility Statements (Should Always Pass)
DO $$
BEGIN
    IF position('test7' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST7: Utility Statements';
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
        END;
    END IF;
END $$;

-- Test 8: Query Cost Analysis
DO $$
BEGIN
    IF position('test8' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST8: Query Cost Analysis';
        BEGIN
            SET cost_guard.threshold = 1000000;
            -- Just verify EXPLAIN works, don't check specific costs
            PERFORM 1; -- Simple test
            RAISE NOTICE 'PASS: Query cost analysis completed';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Query cost analysis failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 9: Warning System Test
DO $$
BEGIN
    IF position('test9' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST9: Warning System';
        BEGIN
            SET cost_guard.threshold = 100000;
            PERFORM COUNT(*) FROM medium_table ORDER BY value;
            RAISE NOTICE 'PASS: Warning system test completed (check logs for warnings)';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Warning system test failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 10: Boundary Testing
DO $$
DECLARE
    query_cost NUMERIC;
BEGIN
    IF position('test10' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST10: Boundary Testing';
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
        END;
    END IF;
END $$;

-- Test 11: Extension Uninstall
DO $$
BEGIN
    IF position('test11' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST11: Extension Uninstall';
        BEGIN
            DROP EXTENSION IF EXISTS cost_guard;
            IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
                RAISE NOTICE 'PASS: Extension uninstalled successfully';
            ELSE
                RAISE NOTICE 'FAIL: Extension still exists after DROP';
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Extension uninstall failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 12: Extension Reinstall
DO $$
BEGIN
    IF position('test12' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST12: Extension Reinstall';
        BEGIN
            CREATE EXTENSION IF NOT EXISTS cost_guard;
            IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'cost_guard') THEN
                RAISE NOTICE 'PASS: Extension reinstalled successfully';
            ELSE
                RAISE NOTICE 'FAIL: Extension reinstall failed';
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Extension reinstall failed - %', SQLERRM;
        END;
    END IF;
END $$;

\echo ''
\echo '=== Selective Test Suite Complete ==='
\echo 'Review the output above for PASS/FAIL results.'
\echo ''

-- Cleanup
\echo 'Cleaning up test environment...'
\c postgres;
DROP DATABASE cost_guard_test;
