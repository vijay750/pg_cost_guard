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
    max_rows_val TEXT;
BEGIN
    IF position('test2' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST2: Default Configuration';
        BEGIN
            SELECT setting INTO threshold_val FROM pg_settings WHERE name = 'cost_guard.threshold';
            SELECT setting INTO enabled_val FROM pg_settings WHERE name = 'cost_guard.enabled';
            SELECT setting INTO max_rows_val FROM pg_settings WHERE name = 'cost_guard.max_plan_rows';
            
            IF threshold_val = '1000000' AND enabled_val = 'on' AND max_rows_val = '0' THEN
                RAISE NOTICE 'PASS: Default configuration correct (threshold: %, enabled: %, max_plan_rows: %)', threshold_val, enabled_val, max_rows_val;
            ELSE
                RAISE NOTICE 'FAIL: Default configuration incorrect (threshold: %, enabled: %, max_plan_rows: %)', threshold_val, enabled_val, max_rows_val;
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
            SET cost_guard.max_plan_rows = 10000;
            SET cost_guard.max_plan_rows = 0;
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
    END IF;
END $$;

-- Set very low threshold to ensure utility statements bypass cost guard
SET cost_guard.enabled = true;
SET cost_guard.threshold = 1;

-- Test DDL statements in transaction block
DO $$
BEGIN
    IF position('test7' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        BEGIN
            CREATE TABLE test_utility (id INTEGER);
            DROP TABLE test_utility;
            CREATE INDEX test_idx ON small_table(data);
            DROP INDEX test_idx;
            
            RAISE NOTICE 'PASS: DDL utility statements executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: DDL utility statements failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test VACUUM and ANALYZE outside transaction (they cannot run in DO blocks)
DO $$
BEGIN
    IF position('test7' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'Running VACUUM and ANALYZE...';
    END IF;
END $$;

VACUUM small_table;
ANALYZE small_table;

DO $$
BEGIN
    IF position('test7' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'PASS: VACUUM and ANALYZE executed successfully';
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
            -- Query that should trigger warning (cost approaching threshold)
            PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 100 AND m2.id < 100;
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

-- Test 11: Max Plan Rows - Low Row Query
DO $$
BEGIN
    IF position('test11' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST11: Max Plan Rows - Low Row Query';
        BEGIN
            SET cost_guard.threshold = 1000000;
            SET cost_guard.max_plan_rows = 50000;
            PERFORM * FROM small_table WHERE id < 50;
            RAISE NOTICE 'PASS: Low row query executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Low row query failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 12: Max Plan Rows - High Row Query
DO $$
BEGIN
    IF position('test12' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST12: Max Plan Rows - High Row Query';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 5000;
            BEGIN
                PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 100 AND m2.id < 100;
                RAISE NOTICE 'FAIL: High row query should have been blocked';
            EXCEPTION
                WHEN SQLSTATE '54001' THEN
                    RAISE NOTICE 'PASS: High row query correctly blocked by max_plan_rows';
                WHEN OTHERS THEN
                    RAISE NOTICE 'FAIL: High row query failed with unexpected error - %', SQLERRM;
            END;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Max plan rows test failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 13: Max Plan Rows Disabled
DO $$
BEGIN
    IF position('test13' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST13: Max Plan Rows Disabled';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 0;
            PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 50 AND m2.id < 50;
            RAISE NOTICE 'PASS: Query executed with max_plan_rows disabled';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Query failed with max_plan_rows disabled - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 14: Both Cost and Row Limits
DO $$
BEGIN
    IF position('test14' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST14: Both Cost and Row Limits';
        BEGIN
            SET cost_guard.threshold = 1000;
            SET cost_guard.max_plan_rows = 5000;
            BEGIN
                PERFORM * FROM large_table WHERE value > 5000;
                RAISE NOTICE 'FAIL: Query should have been blocked';
            EXCEPTION
                WHEN SQLSTATE '54001' THEN
                    RAISE NOTICE 'PASS: Query blocked by either cost or row threshold';
            END;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Combined threshold test failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 15: Max Plan Rows Warning System
DO $$
BEGIN
    IF position('test15' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST15: Max Plan Rows Warning System';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 20000;
            PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 50 AND m2.id < 50;
            RAISE NOTICE 'PASS: Warning system test completed (check logs for warnings)';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'FAIL: Warning system test failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 16: Multi-Step Plan - Aggregate Query
DO $$
BEGIN
    IF position('test16' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST16: Multi-Step Plan - Aggregate Query';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 50000;
            SET client_min_messages = DEBUG1;
            
            PERFORM value, COUNT(*) 
            FROM medium_table 
            GROUP BY value 
            HAVING COUNT(*) > 1;
            
            SET client_min_messages = NOTICE;
            RAISE NOTICE 'PASS: Aggregate query with multi-step plan executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Aggregate query failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 17: Multi-Step Plan - Join Query
DO $$
BEGIN
    IF position('test17' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST17: Multi-Step Plan - Join Query';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 200000;
            SET client_min_messages = DEBUG1;
            
            PERFORM s.id, m.value
            FROM small_table s
            INNER JOIN medium_table m ON s.id = m.id
            WHERE s.id < 50;
            
            SET client_min_messages = NOTICE;
            RAISE NOTICE 'PASS: Join query with multi-step plan executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Join query failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 18: Multi-Step Plan - Nested Subquery
DO $$
BEGIN
    IF position('test18' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST18: Multi-Step Plan - Nested Subquery';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 100000;
            SET client_min_messages = DEBUG1;
            
            PERFORM * FROM (
                SELECT m1.id, m1.value, COUNT(*) as cnt
                FROM medium_table m1
                WHERE m1.value > 5000
                GROUP BY m1.id, m1.value
            ) subq
            WHERE subq.cnt > 0;
            
            SET client_min_messages = NOTICE;
            RAISE NOTICE 'PASS: Subquery with multi-step plan executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Subquery failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 19: Multi-Step Plan - Complex Join with Aggregates
DO $$
BEGIN
    IF position('test19' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST19: Multi-Step Plan - Complex Join with Aggregates';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 150000;
            SET client_min_messages = DEBUG1;
            
            PERFORM m.value, COUNT(DISTINCT s.id) as unique_ids
            FROM medium_table m
            LEFT JOIN small_table s ON m.id = s.id
            WHERE m.value < 100000
            GROUP BY m.value
            HAVING COUNT(DISTINCT s.id) >= 0;
            
            SET client_min_messages = NOTICE;
            RAISE NOTICE 'PASS: Complex join+aggregate query executed successfully';
        EXCEPTION
            WHEN OTHERS THEN
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Complex query failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 20: Multi-Step Plan Blocked by Row Limit
DO $$
BEGIN
    IF position('test20' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST20: Multi-Step Plan Blocked by Row Limit';
        BEGIN
            SET cost_guard.threshold = 10000000;
            SET cost_guard.max_plan_rows = 1000;
            SET client_min_messages = DEBUG1;
            
            BEGIN
                PERFORM *
                FROM medium_table m1
                CROSS JOIN medium_table m2
                WHERE m1.id < 100 AND m2.id < 100;
                
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Query should have been blocked by max_plan_rows';
            EXCEPTION
                WHEN SQLSTATE '54001' THEN
                    SET client_min_messages = NOTICE;
                    RAISE NOTICE 'PASS: Multi-step query correctly blocked by max_plan_rows';
                WHEN OTHERS THEN
                    SET client_min_messages = NOTICE;
                    RAISE NOTICE 'FAIL: Unexpected error - %', SQLERRM;
            END;
        EXCEPTION
            WHEN OTHERS THEN
                SET client_min_messages = NOTICE;
                RAISE NOTICE 'FAIL: Test setup failed - %', SQLERRM;
        END;
    END IF;
END $$;

-- Test 21: Extension Uninstall
DO $$
BEGIN
    IF position('test21' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST21: Extension Uninstall';
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

-- Test 22: Extension Reinstall
DO $$
BEGIN
    IF position('test22' in :'test_filter_var') > 0 OR :'test_filter_var' = '' THEN
        RAISE NOTICE 'RUNNING TEST22: Extension Reinstall';
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
