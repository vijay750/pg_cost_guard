MODULE_big = cost_guard
OBJS = cost_guard.o

EXTENSION = cost_guard
DATA = cost_guard--1.0.sql

# Force use of PGXS for building outside PostgreSQL source tree
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
