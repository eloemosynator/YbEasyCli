CREATE OR REPLACE PROCEDURE yb_chunk_dml_by_integer_lowcard_p(
    a_table                 VARCHAR
    , a_integer_column      VARCHAR
    , a_dml                 VARCHAR
    , a_table_where_clause  VARCHAR DEFAULT 'TRUE'
    , a_min_chunk_size      BIGINT
    , a_verbose             BOOLEAN DEFAULT TRUE
    , a_add_null_chunk      BOOLEAN DEFAULT TRUE
    , a_print_chunk_dml     BOOLEAN DEFAULT FALSE
    , a_execute_chunk_dml   BOOLEAN DEFAULT FALSE )
    RETURNS BOOLEAN
    LANGUAGE plpgsql
AS $$
-- chunks data where a_interger_column_name column contains lower cardinality data
--     where a column value may have 1000 or more rows
DECLARE
    v_rc REFCURSOR;
    v_rec RECORD;
    v_chunk_first_val    BIGINT;
    v_total_size         BIGINT;
    v_null_count         BIGINT;
    v_running_total_size BIGINT := 0;
    v_chunk              BIGINT := 0;
    v_chunk_size         BIGINT := 0;
    v_chunk_max_size     BIGINT := 0;
    v_exec_dml           TEXT;
    v_sql_rowcount       BIGINT;
    v_sql_where_clause   TEXT := REPLACE(
'/* chunk_clause(chunk: <chunk>, size: <chunk_size>) >>>*/ <chunk_first_val> <= <integer_column> AND <integer_column> < <chunk_last_val> /*<<< chunk_clause */'
        , '<integer_column>', a_integer_column);
    v_sql_select_total_size TEXT := REPLACE(REPLACE(
'SELECT COUNT(*) AS total_size FROM <table> WHERE <table_where_clause>'
        , '<table>', a_table)
        , '<table_where_clause>', a_table_where_clause);
    v_sql_select_null_count TEXT := REPLACE(REPLACE(REPLACE(
'SELECT COUNT(*) AS null_count FROM <table> WHERE <integer_column> IS NULL AND <table_where_clause> AND <table_where_clause>'
        , '<table>', a_table)
        , '<integer_column>', a_integer_column)
        , '<table_where_clause>', a_table_where_clause);
    v_sql_create_tmp_group_table TEXT := REPLACE(REPLACE(REPLACE(
'DROP TABLE IF EXISTS chunked_groups;
CREATE TEMPORARY TABLE chunked_groups AS
SELECT
    <integer_column> AS start_val
    , COUNT(*) AS cnt
FROM <table>
WHERE <table_where_clause>
GROUP BY 1
DISTRIBUTE ON (start_val)'
        , '<table>', a_table)
        , '<integer_column>', a_integer_column)
        , '<table_where_clause>', a_table_where_clause);
    v_sql_create_tmp_group_w_lead_table TEXT := 
'DROP TABLE IF EXISTS group_w_lead;
CREATE TEMPORARY TABLE group_w_lead AS
    SELECT
        start_val
        , LEAD(start_val, 1) OVER (ORDER BY start_val) AS next_val
        , cnt
        , ROW_NUMBER() OVER (ORDER BY start_val) AS rn
    FROM chunked_groups
DISTRIBUTE ON (start_val)';
    v_sql_fold_groups_sql_fold_groups Text := 
'DROP TABLE IF EXISTS folded_groups;
CREATE TEMP TABLE folded_groups AS
WITH
folded AS (
    SELECT
        g1.start_val, g2.next_val, g1.cnt + g2.cnt AS cnt
        , g2.start_val AS delete_start_val
    FROM
        group_w_lead AS g1
        JOIN group_w_lead AS g2
            ON g1.next_val = g2.start_val
    WHERE
        g1.rn % 2 = 1
        AND g1.cnt + g2.cnt < 1000000
        AND g1.next_val IS NOT NULL
        AND g2.next_val IS NOT NULL
)
, new_groups AS (
    SELECT
        start_val, next_val, cnt
    FROM
        group_w_lead
    WHERE
        start_val NOT IN (SELECT start_val FROM folded)
        AND start_val NOT IN (SELECT delete_start_val FROM folded)
    UNION ALL
    SELECT
        start_val, next_val, cnt
    FROM
        folded
)
SELECT
    start_val, next_val, cnt
    , ROW_NUMBER() OVER (ORDER BY start_val) AS rn
FROM
    new_groups
DISTRIBUTE ON (start_val)
';
    v_sql_select_groups TEXT := 
'SELECT
    start_val
    , NVL(next_val, start_val + 1) AS next_val  
    , NVL2(next_val, FALSE, TRUE) AS is_last_rec
    , cnt
FROM group_w_lead
ORDER BY 1
';
    v_start_ts     TIMESTAMP := CLOCK_TIMESTAMP();
    v_dml_start_ts TIMESTAMP;
    v_dml_total_duration INTERVAL := INTERVAL '0 DAYS';
BEGIN
    IF a_verbose = TRUE THEN RAISE INFO '--%: Starting Integer Chunking, first calculating group counts', CLOCK_TIMESTAMP(); END IF;
    --
    EXECUTE v_sql_select_total_size INTO v_total_size;
    EXECUTE v_sql_select_null_count INTO v_null_count;
    --
    --
    -- first pass on chunk grouping, gets the number of groups to under 1,000,000
    IF a_verbose = TRUE THEN RAISE INFO '--%: Build Chunk Groupings, first pass', CLOCK_TIMESTAMP(); END IF;
    --
    EXECUTE v_sql_create_tmp_group_table;
    EXECUTE v_sql_create_tmp_group_w_lead_table;
    EXECUTE 'SELECT COUNT(*) FROM group_w_lead' INTO v_sql_rowcount;
    LOOP
        EXIT WHEN v_sql_rowcount < 1000000;
        EXECUTE v_sql_fold_groups_sql_fold_groups;
        DROP TABLE group_w_lead;
        ALTER TABLE folded_groups RENAME TO group_w_lead;
        EXECUTE 'SELECT COUNT(*) FROM group_w_lead' INTO v_sql_rowcount;
    END LOOP;
    --
    OPEN v_rc FOR EXECUTE v_sql_select_groups;
    --RAISE INFO '--%: SQL :% ', CLOCK_TIMESTAMP(), v_sql_select_groups; --DEBUG
    FETCH NEXT FROM v_rc INTO v_rec;
    v_chunk_first_val := v_rec.start_val;
    --
    --
    -- second pass on chunk grouping, gets final groups to a_min_chunk_size
    IF a_verbose = TRUE THEN RAISE INFO '--%: Build Chunk DMLs', CLOCK_TIMESTAMP(); END IF;
    --
    LOOP
        EXIT WHEN v_rec.is_last_rec IS NULL; --no chunks because a_table is empty
        v_chunk_size := v_chunk_size + v_rec.cnt;
        IF v_chunk_size >= a_min_chunk_size OR v_rec.is_last_rec THEN
            v_chunk := v_chunk + 1;
            IF v_chunk_size > v_chunk_max_size THEN
                v_chunk_max_size := v_chunk_size;
            END IF;
            --
            IF a_verbose = TRUE THEN
                RAISE INFO '--%: Chunk: %, Rows: %, Range % <= % < %', CLOCK_TIMESTAMP(), v_chunk, v_chunk_size, v_chunk_first_val, a_integer_column, v_rec.next_val;
            END IF;
            --
            v_exec_dml := REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(a_dml,'<chunk_where_clause>', v_sql_where_clause), '<chunk_first_val>', v_chunk_first_val::VARCHAR), '<chunk_last_val>',  v_rec.next_val::VARCHAR), '<chunk_size>', v_chunk_size::VARCHAR), '<chunk>', v_chunk::VARCHAR);
            --
            IF a_print_chunk_dml = TRUE THEN RAISE INFO '%;', v_exec_dml; END IF;
            --
            IF a_execute_chunk_dml = TRUE THEN
                v_dml_start_ts := CLOCK_TIMESTAMP();
                EXECUTE v_exec_dml;
                v_dml_total_duration := v_dml_total_duration + (CLOCK_TIMESTAMP() - v_dml_start_ts);
            END IF;
            --
            v_running_total_size := v_running_total_size + v_chunk_size;
            EXIT WHEN v_rec.is_last_rec;
            --
            v_chunk_first_val := v_rec.next_val;
            v_chunk_size := 0;
        END IF;
        --RAISE INFO '%', v_rec;
        FETCH NEXT FROM v_rc INTO v_rec;
    END LOOP;
    CLOSE v_rc;
    --
    IF a_add_null_chunk = TRUE THEN
        v_chunk := v_chunk + 1;
        --
        IF a_verbose = TRUE THEN
            RAISE INFO '--%: Chunk: %, Rows: %, % IS NULL', CLOCK_TIMESTAMP(), v_chunk, v_null_count, a_integer_column;
        END IF;
        --
        v_exec_dml := REPLACE(a_dml, '<chunk_where_clause>', a_integer_column || ' IS NULL');
        --
        IF a_print_chunk_dml = TRUE THEN
            RAISE INFO '%;', v_exec_dml;
        END IF;
        --
        IF a_execute_chunk_dml = TRUE THEN
            v_dml_start_ts := CLOCK_TIMESTAMP();
            EXECUTE v_exec_dml;
            v_dml_total_duration := v_dml_total_duration + (CLOCK_TIMESTAMP() - v_dml_start_ts);
        END IF;
        --
        v_running_total_size := v_running_total_size + v_null_count;
    END IF;
    --
    IF a_verbose = TRUE THEN
        RAISE INFO '--%: Completed Integer Chunked DML', CLOCK_TIMESTAMP();
        IF a_add_null_chunk = FALSE AND v_null_count <> 0 THEN
            RAISE INFO '--******WARNING******: There are records with NULL vales and you have not requested for a NULL chunk!';
        END IF;
        RAISE INFO '--Total Rows         : %', v_total_size;
        RAISE INFO '--IS NULL Rows       : %', v_null_count;
        RAISE INFO '--Running total check: %', DECODE(TRUE, (DECODE(TRUE, a_add_null_chunk, v_total_size, v_total_size - v_null_count) = v_running_total_size), 'PASSED', 'FAILED');
        RAISE INFO '--Duration           : %', CLOCK_TIMESTAMP() - v_start_ts;
        RAISE INFO '--Overhead duration  : %', (CLOCK_TIMESTAMP() - v_start_ts) - v_dml_total_duration;
        RAISE INFO '--Total Chunks       : %', v_chunk;
        RAISE INFO '--Min chunk size     : %', a_min_chunk_size;
        RAISE INFO '--Largest chunk size : %', v_chunk_max_size;
        RAISE INFO '--Average chunk size : %', DECODE(v_chunk, 0, 0, v_running_total_size / v_chunk);
    END IF;
    --
    RETURN (v_total_size = v_running_total_size);
END$$;