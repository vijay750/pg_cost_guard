#include "postgres.h"
#include "fmgr.h"
#include "utils/guc.h"
#include "optimizer/planner.h"
#include "nodes/plannodes.h"
#include "utils/elog.h"
#include "miscadmin.h"
#include <float.h>

PG_MODULE_MAGIC;

/* GUC variables */
static double cost_threshold = 1000000.0;  /* Default threshold */
static bool cost_guard_enabled = true;

/* Hook storage */
static planner_hook_type prev_planner_hook = NULL;

/* Function declarations */
void _PG_init(void);
void _PG_fini(void);
static PlannedStmt *cost_guard_planner_hook(Query *parse,
                                           const char *query_string,
                                           int cursorOptions,
                                           ParamListInfo boundParams);

/*
 * Module initialization function
 */
void
_PG_init(void)
{
    /* Define custom GUC parameters */
    DefineCustomRealVariable("cost_guard.threshold",
                            "Maximum allowed query cost",
                            "Queries with estimated cost above this value will be rejected",
                            &cost_threshold,
                            1000000.0,  /* default */
                            0.0,        /* min */
                            DBL_MAX,    /* max */
                            PGC_SUSET,  /* context */
                            0,          /* flags */
                            NULL,       /* check_hook */
                            NULL,       /* assign_hook */
                            NULL);      /* show_hook */

    DefineCustomBoolVariable("cost_guard.enabled",
                            "Enable/disable cost guard",
                            "When enabled, queries exceeding cost threshold will be rejected",
                            &cost_guard_enabled,
                            true,       /* default */
                            PGC_SUSET,  /* context */
                            0,          /* flags */
                            NULL,       /* check_hook */
                            NULL,       /* assign_hook */
                            NULL);      /* show_hook */

    /* Install planner hook */
    prev_planner_hook = planner_hook;
    planner_hook = cost_guard_planner_hook;

    elog(LOG, "cost_guard extension loaded");
}

/*
 * Module cleanup function
 */
void
_PG_fini(void)
{
    /* Restore previous planner hook */
    planner_hook = prev_planner_hook;
    
    elog(LOG, "cost_guard extension unloaded");
}

/*
 * Custom planner hook function
 */
static PlannedStmt *
cost_guard_planner_hook(Query *parse,
                       const char *query_string,
                       int cursorOptions,
                       ParamListInfo boundParams)
{
    PlannedStmt *result;
    Cost        total_cost;

    /* Call the previous planner hook or standard planner */
    if (prev_planner_hook)
        result = prev_planner_hook(parse, query_string, cursorOptions, boundParams);
    else
        result = standard_planner(parse, query_string, cursorOptions, boundParams);

    /* Check if cost guard is enabled */
    if (!cost_guard_enabled)
        return result;

    /* Skip cost checking for utility statements */
    if (!result || !result->planTree)
        return result;

    /* Get the total cost of the plan */
    total_cost = result->planTree->total_cost;

    /* Check if cost exceeds threshold */
    if (total_cost > cost_threshold)
    {
        ereport(ERROR,
                (errcode(ERRCODE_STATEMENT_TOO_COMPLEX),
                 errmsg("query cost %.2f exceeds threshold %.2f",
                        total_cost, cost_threshold),
                 errhint("Consider optimizing the query or increasing cost_guard.threshold")));
    }

    /* Log expensive queries that are still under threshold */
    if (total_cost > (cost_threshold * 0.8))
    {
        elog(WARNING, "expensive query detected: cost %.2f (threshold: %.2f)",
             total_cost, cost_threshold);
    }

    return result;
}
