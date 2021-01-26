#!/usr/bin/env python3
"""
USAGE:
      yb_get_sequence_names.py [database] [options]

PURPOSE:
      List the sequence names found in this database.

OPTIONS:
      See the command line help message for all options.
      (yb_get_sequence_names.py --help)

Output:
      The names of all sequences will be listed out, one per line.
"""
from yb_util import util

class get_sequence_names(util):
    """Issue the ybsql command to list the sequences found in a particular
    database.
    """
    config = {
        'description': 'List/Verifies that the specified sequence/s exist.'
        , 'optional_args_single': ['database']
        , 'optional_args_multi': ['owner', 'schema', 'sequence']
        , 'usage_example': {
            'cmd_line_args': "@$HOME/conn.args --schema_in dev Prod --sequence_like '%price%' --sequence_NOTlike '%id%' --"
            , 'file_args': [util.conn_args_file] }
        , 'default_args': {'template': '{sequence_path}', 'exec_output': False}
        , 'output_tmplt_vars': ['sequence_path', 'schema_path', 'sequence', 'schema', 'database', 'owner']
        , 'output_tmplt_default': '{sequence_path}'
        , 'db_filter_args': {'owner':'owner', 'schema':'schema', 'sequence':'sequence'} }

    def execute(self):
        self.db_filter_args.schema_set_all_if_none()
        sql_query = """
WITH
objct AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY LOWER(n.nspname), LOWER(c.relname)) AS ordinal
        , c.relname AS sequence
        , n.nspname AS schema
        , pg_get_userbyid(c.relowner) AS owner
    FROM {database}.pg_catalog.pg_class AS c
        LEFT JOIN {database}.pg_catalog.pg_namespace AS n
            ON n.oid = c.relnamespace
    WHERE
        schema NOT IN ('sys', 'pg_catalog', 'information_schema')
        AND c.relkind IN ('S')
        AND {filter_clause}
)
SELECT
    DECODE(ordinal, 1, '', ', ')
    || '{{' || '"ordinal": ' || ordinal::VARCHAR || ''
    || ',"owner":""\" '    || owner        || ' ""\"'
    || ',"database":""\" ' || '{database}' || ' ""\"'
    || ',"schema":""\" '   || schema       || ' ""\"'
    || ',"sequence":""\" ' || sequence     || ' ""\"' || '}}' AS data
FROM objct
ORDER BY ordinal""".format(
             filter_clause = self.db_filter_sql()
             , database    = self.db_conn.database)

        return self.exec_query_and_apply_template(sql_query, exec_output=self.args_handler.args.exec_output)

def main():
    gsn = get_sequence_names()
    
    print(gsn.execute())

    exit(gsn.cmd_result.exit_code)


if __name__ == "__main__":
    main()
