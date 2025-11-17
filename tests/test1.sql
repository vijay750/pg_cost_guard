-- Test 1: Extension Installation
\echo 'TEST1: Testing extension installation...'
DO $$
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
END $$;
