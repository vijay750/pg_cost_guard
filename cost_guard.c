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
static double max_plan_rows = 0.0;  /* Default: no limit (0 = disabled) */

/* Hook storage */
static planner_hook_type prev_planner_hook = NULL;

/* Function declarations */
void _PG_init(void);
void _PG_fini(void);
static PlannedStmt *cost_guard_planner_hook(Query *parse,
                                           const char *query_string,
                                           int cursorOptions,
                                           ParamListInfo boundParams);
static double find_max_plan_rows(Plan *plan);

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

    DefineCustomRealVariable("cost_guard.max_plan_rows",
                            "Maximum allowed estimated rows in query plan",
                            "Queries with estimated rows above this value will be rejected (0 = no limit)",
                            &max_plan_rows,
                            0.0,        /* default (disabled) */
                            0.0,        /* min */
                            DBL_MAX,    /* max */
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
    double      max_rows;

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

    /* Get the maximum estimated rows from the plan tree */
    max_rows = find_max_plan_rows(result->planTree);

    /* Check if cost exceeds threshold */
    if (total_cost > cost_threshold)
    {
        ereport(ERROR,
                (errcode(ERRCODE_STATEMENT_TOO_COMPLEX),
                 errmsg("query cost %.2f exceeds threshold %.2f",
                        total_cost, cost_threshold),
                 errhint("Consider optimizing the query or increasing cost_guard.threshold")));
    }

    /* Check if max rows exceeds threshold (if enabled) */
    if (max_plan_rows > 0 && max_rows > max_plan_rows)
    {
        ereport(ERROR,
                (errcode(ERRCODE_STATEMENT_TOO_COMPLEX),
                 errmsg("query estimated rows %.0f exceeds threshold %.0f",
                        max_rows, max_plan_rows),
                 errhint("Consider optimizing the query or increasing cost_guard.max_plan_rows")));
    }

    /* Log expensive queries that are still under threshold */
    if (total_cost > (cost_threshold * 0.8))
    {
        elog(WARNING, "expensive query detected: cost %.2f (threshold: %.2f)",
             total_cost, cost_threshold);
    }

    return result;
}

/*
 * Recursively traverse the plan tree to find the maximum estimated rows
 * from any node in the tree.
 */
static double
find_max_plan_rows(Plan *plan)
{
    double max_rows;
    double child_max;

    if (plan == NULL)
        return 0.0;

    /* Start with this node's row estimate */
    max_rows = plan->plan_rows;
    
    /* Log this node's row estimate */
    elog(DEBUG1, "Plan node type %d: estimated rows = %.0f", nodeTag(plan), plan->plan_rows);

    /* Check left subtree */
    if (plan->lefttree)
    {
        child_max = find_max_plan_rows(plan->lefttree);
        if (child_max > max_rows)
        {
            elog(DEBUG1, "Left subtree has higher row estimate: %.0f > %.0f", child_max, max_rows);
            max_rows = child_max;
        }
    }

    /* Check right subtree */
    if (plan->righttree)
    {
        child_max = find_max_plan_rows(plan->righttree);
        if (child_max > max_rows)
        {
            elog(DEBUG1, "Right subtree has higher row estimate: %.0f > %.0f", child_max, max_rows);
            max_rows = child_max;
        }
    }

    return max_rows;
}
