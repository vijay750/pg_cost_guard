-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION cost_guard" to load this file. \quit

-- This extension doesn't create any SQL objects, it only provides hooks
-- The configuration is done via GUC parameters:
-- cost_guard.threshold - maximum allowed query cost (default: 1000000.0)
-- cost_guard.enabled - enable/disable the cost guard (default: true)
-- cost_guard.max_plan_rows - maximum allowed estimated rows in query plan (default: 0, meaning no limit)
