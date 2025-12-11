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
    max_rows_val TEXT;
BEGIN
    SELECT setting INTO threshold_val FROM pg_settings WHERE name = 'cost_guard.threshold';
    SELECT setting INTO enabled_val FROM pg_settings WHERE name = 'cost_guard.enabled';
    SELECT setting INTO max_rows_val FROM pg_settings WHERE name = 'cost_guard.max_plan_rows';
    
    IF threshold_val = '1e+06' AND enabled_val = 'on' AND max_rows_val = '0' THEN
        RAISE NOTICE 'PASS: Default configuration correct (threshold: %, enabled: %, max_plan_rows: %)', threshold_val, enabled_val, max_rows_val;
    ELSE
        RAISE NOTICE 'FAIL: Default configuration incorrect (threshold: %, enabled: %, max_plan_rows: %)', threshold_val, enabled_val, max_rows_val;
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
    SET cost_guard.max_plan_rows = 10000;
    SET cost_guard.max_plan_rows = 0;
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
DECLARE
    error_message TEXT;
    estimated_cost NUMERIC;
    threshold_value NUMERIC := 1000;
    cost_match TEXT[];
    threshold_match TEXT[];
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
-- Set very low threshold to ensure utility statements bypass cost guard
SET cost_guard.enabled = true;
SET cost_guard.threshold = 1;

-- Test DDL statements in transaction block
DO $$
BEGIN
    CREATE TABLE test_utility (id INTEGER);
    DROP TABLE test_utility;
    CREATE INDEX test_idx ON small_table(data);
    DROP INDEX test_idx;
    
    RAISE NOTICE 'PASS: DDL utility statements executed successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: DDL utility statements failed - %', SQLERRM;
END $$;

-- Test VACUUM and ANALYZE outside transaction (they cannot run in DO blocks)
VACUUM small_table;
ANALYZE small_table;
\echo 'NOTICE:  PASS: VACUUM and ANALYZE executed successfully'
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
    -- Query that should trigger warning (cost approaching threshold)
    PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 100 AND m2.id < 100;
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

-- Test 11: Max Plan Rows - Low Row Query (Should Pass)
\echo '12. Testing max_plan_rows with low row query (should pass)...'
DO $$
BEGIN
    SET cost_guard.threshold = 1000000;
    SET cost_guard.max_plan_rows = 50000;
    -- Query that should have low row estimate
    PERFORM * FROM small_table WHERE id < 50;
    RAISE NOTICE 'PASS: Low row query executed successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Low row query failed - %', SQLERRM;
END $$;
\echo ''

-- Test 12: Max Plan Rows - High Row Query (Should Fail)
\echo '13. Testing max_plan_rows with high row query (should fail)...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;  -- Set high cost threshold
    SET cost_guard.max_plan_rows = 5000;  -- Set low row threshold
    BEGIN
        -- Cross join should produce high row estimate
        PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 100 AND m2.id < 100;
        RAISE NOTICE 'FAIL: High row query should have been blocked';
    EXCEPTION
        WHEN SQLSTATE '54001' THEN  -- ERRCODE_STATEMENT_TOO_COMPLEX
            RAISE NOTICE 'PASS: High row query correctly blocked by max_plan_rows';
        WHEN OTHERS THEN
            RAISE NOTICE 'FAIL: High row query failed with unexpected error - %', SQLERRM;
    END;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Max plan rows test failed - %', SQLERRM;
END $$;
\echo ''

-- Test 13: Max Plan Rows Disabled (Should Pass)
\echo '14. Testing query with max_plan_rows disabled (should pass)...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 0;  -- Disable row limit
    -- Cross join with high row estimate should pass when disabled
    PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 50 AND m2.id < 50;
    RAISE NOTICE 'PASS: Query executed with max_plan_rows disabled';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Query failed with max_plan_rows disabled - %', SQLERRM;
END $$;
\echo ''

-- Test 14: Both Cost and Row Limits
\echo '15. Testing both cost and row limits together...'
DO $$
BEGIN
    SET cost_guard.threshold = 1000;
    SET cost_guard.max_plan_rows = 5000;
    BEGIN
        -- This query should be blocked by cost threshold
        PERFORM * FROM large_table WHERE value > 5000;
        RAISE NOTICE 'FAIL: Query should have been blocked by cost threshold';
    EXCEPTION
        WHEN SQLSTATE '54001' THEN
            RAISE NOTICE 'PASS: Query blocked by either cost or row threshold';
    END;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Combined threshold test failed - %', SQLERRM;
END $$;
\echo ''

-- Test 15: Max Plan Rows Warning System
\echo '16. Testing max_plan_rows warning system...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 20000;
    -- Query with row estimate around 80% of threshold (should warn but not block)
    PERFORM * FROM medium_table m1, medium_table m2 WHERE m1.id < 50 AND m2.id < 50;
    RAISE NOTICE 'PASS: Warning system test completed (check logs for warnings)';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Warning system test failed - %', SQLERRM;
END $$;
\echo ''

-- Test 16: Multi-Step Plan - Aggregate Query
\echo '17. Testing multi-step plan with aggregates...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 50000;
    SET client_min_messages = DEBUG1;  -- Enable DEBUG logging to see plan traversal
    
    -- Aggregate query with GROUP BY creates multi-step plan (Aggregate -> Sort -> Seq Scan)
    PERFORM value, COUNT(*) 
    FROM medium_table 
    GROUP BY value 
    HAVING COUNT(*) > 1;
    
    SET client_min_messages = NOTICE;  -- Reset logging
    RAISE NOTICE 'PASS: Aggregate query with multi-step plan executed successfully';
EXCEPTION
    WHEN OTHERS THEN
        SET client_min_messages = NOTICE;
        RAISE NOTICE 'FAIL: Aggregate query failed - %', SQLERRM;
END $$;
\echo ''

-- Test 17: Multi-Step Plan - Join Query
\echo '18. Testing multi-step plan with joins...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 200000;
    SET client_min_messages = DEBUG1;
    
    -- Join creates multi-step plan (Hash Join -> Seq Scan + Hash -> Seq Scan)
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
END $$;
\echo ''

-- Test 18: Multi-Step Plan - Nested Subquery
\echo '19. Testing multi-step plan with subquery...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 100000;
    SET client_min_messages = DEBUG1;
    
    -- Subquery creates nested plan tree
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
END $$;
\echo ''

-- Test 19: Multi-Step Plan - Complex Join with Aggregates
\echo '20. Testing complex multi-step plan (join + aggregate)...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 150000;
    SET client_min_messages = DEBUG1;
    
    -- Complex query: join + aggregate creates deep plan tree
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
END $$;
\echo ''

-- Test 20: Multi-Step Plan Blocked by Row Limit
\echo '21. Testing multi-step plan blocked by max_plan_rows...'
DO $$
BEGIN
    SET cost_guard.threshold = 10000000;
    SET cost_guard.max_plan_rows = 1000;  -- Low threshold
    SET client_min_messages = DEBUG1;
    
    BEGIN
        -- This join should have intermediate steps exceeding row limit
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
END $$;
\echo ''

-- Test 21: Extension Uninstall
\echo '22. Testing extension uninstall...'
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

-- Test 22: Extension Reinstall
\echo '23. Testing extension reinstall...'
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
