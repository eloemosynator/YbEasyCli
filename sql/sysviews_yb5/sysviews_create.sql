/* sysviews_create.sql
**
** ybsql script for Yellowbrick Version 5 to run sysview procedure DDLs to:
** . set the default search_path to PUBLIC, and pg_catalog
** . create the procedures
**
** To grant default permissions on the procedures, run sysviews_grant.sql .
**
** Version history:
** . 2021.12.09 - ybCliUtils inclusion.
** . 2021.05.07 - Yellowbrick Technical Support
** . 2021.05.07 - For Yellowbrick version >= 5.0 only.
*/

\echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SET search_path TO public,pg_catalog;
CREATE DATABASE sysviews ENCODING UTF8;
\c sysviews

SELECT LEFT( setting, 1 ) AS ver_m FROM pg_settings WHERE name = 'yb_server_version' ;
\gset

\echo
\echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
\echo Running stored proc creation scripts for major version :ver_m

\echo Create the sysviews_settings table
\i  sysviews_settings.sql

\echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
\echo Create the stored procedures
\i  sql_inject_check_p.sql
\i  all_user_objs_p.sql
\i  analyze_immed_user_p.sql
\i  analyze_immed_sess_p.sql
\i  bulk_xfer_p.sql
\i  column_dstr_p.sql
\i  column_stats_p.sql
\i  help_p.sql
\i  load_p.sql
\i  log_bulk_xfer_p.sql
\i  log_query_p.sql
\i  log_query_pivot_p.sql
\i  log_query_smry_p.sql
\i  log_query_steps_p.sql
\i  log_query_timing_p.sql
\i  procedure_p.sql
\i  query_p.sql
\i  query_steps_p.sql
\i  rel_p.sql
\i  rowstore_p.sql
\i  rowstore_by_table_p.sql
\i  schema_p.sql
\i  session_p.sql
\i  session_smry_p.sql
\i  storage_by_db_p.sql
\i  storage_by_schema_p.sql
\i  storage_by_table_p.sql
\i  storage_p.sql
\i  sysviews_p.sql
\i  table_constraints_p.sql
\i  table_skew_p.sql
--\i  table_deps_p.sql
--\i  view_ddls_p.sql
\i  wlm_active_profile_p.sql
\i  wlm_active_rule_p.sql
\i  wlm_state_p.sql
\echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
\echo
\q 
