#!/usr/bin/env python3
"""
USAGE:
      yb_is_cstore_table.py [options]

PURPOSE:
      Determine if a table is stored as a column store table

OPTIONS:
      See the command line help message for all options.
      (yb_is_cstore_table.py --help)

Output:
      True/False
"""
import sys
import os
import re

import yb_common
from yb_util import util

class is_cstore_table(util):
    """Issue the ybsql command used to determine if a table is stored as a column store table.
    """

    def execute(self):
        self.cmd_results = self.db_conn.call_stored_proc_as_anonymous_block(
            'yb_is_cstore_table_p'
            , args = {
                'a_tablename' : yb_common.common.quote_object_paths(self.args_handler.args.table)})

        self.cmd_results.write()
        print(self.cmd_results.proc_return)

    def additional_args(self):
        args_required_grp = self.args_handler.args_parser.add_argument_group('required arguments')
        args_required_grp.add_argument(
            "--table", required=True
            , help="table name, the name ot the table to test")

def main():
    iscst = is_cstore_table()

    iscst.execute()

    exit(iscst.cmd_results.exit_code)


if __name__ == "__main__":
    main()