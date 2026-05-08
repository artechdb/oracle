REM ======================
REM sqltunes.sql - SQL Performance Diagnostic Collector for LLM Analysis
REM ======================

REM
REM ABOUT
REM   This script will create a SQL performance metadata "AI Feeder file" that you can drop the file into ANY AI, but we will
REM   use it with COPILOT desktop initially. It will analyze the SQL and may diagnose and recommend solutions.
REM   IT SHOULD BE INTERACTIVE!!!!, so you can ask follow up questions and it will generate more SQL to run to get more data if needed.
REM   BE CRITICAL, ASK QUESTIONS!!!!
REM   The usage of this is only limited by your IMAGINATION and CURIOSITY. The more you ask, the more it will give you, and the better it will get at diagnosing and fixing your SQL problems.

REM
REM PURPOSE
REM   Collects comprehensive performance diagnostics for a single SQL_ID
REM   and writes a plain-text report to SQL_PERF.out suitable for both
REM   human review and LLM-based analysis (target < 200k tokens).

REM
REM ENVIRONMENT
REM   - Oracle 19.21+ on Exadata RAC (2, 4, or 8 node clusters)
REM   - Container databases; run this script inside the target PDB
REM   - Requires DBA role or SELECT on V$ / DBA_HIST views
REM   - Diagnostics Pack fully licensed assumed (AWR/ASH access)

REM
REM PARAMETERS
REM   1. SQL_ID      - The SQL_ID to analyze (required)
REM   2. BEGIN_DATE  - Analysis window start (required). Accepts:
REM                    YYYY-MM-DD [YYYY-MM-DD HH24:MI[:SS]]
REM                    TIMESTAMP 'YYYY-MM-DD HH24:MI:SS'
REM                    or SQL expressions such as: (SYSDATE-1), SYSDATE,
REM                    TRUNC(SYSDATE), TO_DATE('....','....')
REM   3. END_DATE    - Analysis window end (required). Same formats as above.

REM
REM USAGE
REM   @sqltune.sql 312mbujgpj9pu "2026-04-22 13:00" "2026-04-24 14:00"
REM   @sqltune.sql 312mbujgpj9pu 2026-04-22T13:00:00 2026-04-24T14:00:00
REM   @sqltune.sql 312mbujgpj9pu "TIMESTAMP '2026-04-27 08:57:50'" "TIMESTAMP '2026-04-27 15:57:50'"
REM   @sqltune.sql 312mbujgpj9pu "(sysdate -1)" "sysdate"
REM   @sqltune.sql 312mbujgpj9pu "trunc(sysdate)" "sysdate"

REM
REM NOTE
REM   If a timestamp contains spaces, wrap it in double quotes or use
REM   a single-token form such as YYYY-MM-DDTHH24:MI:SS.

REM
REM OUTPUT
REM   SQL_PERF.out (plain text, human + LLM readable)

REM
REM REPORT SECTIONS (in order)
REM   0.  LLM Analysis Instructions and Report Context
REM   0b. Executive Summary (Auto-Generated Key Indicators)
REM   0c. Computed Problem Indicators (Boolean Flags)
REM   1.  Database and Instance Environment
REM   2.  SQL Text
REM   3.  Execution Plans (SGA current + AWR historical)
REM   3d. Cardinality Analysis (E-Rows vs A-Rows comparison)
REM   4.  AWR Historical Execution Summary by Plan Hash (7 days)
REM   5.  Per-Execution Duration Statistics and DB Time Impact
REM   6.  SQL Wait Event Profile (ASH)
REM   7.  Wait Event Shift Analysis (Problem vs Baseline)
REM   8.  System-Wide Top Waits and Top SQL
REM   9.  Table Statistics
REM   10. Index Statistics
REM   11. Column and Histogram Statistics for Predicates
REM   12. SQL Plan Baselines, Profiles, Patches and Quarantine
REM   13. Resource Manager, Parallel Execution and Throttling

REM
REM VERSION
REM   1 2026-04-28 Reset version to 1
REM   1 2026-04-29 Version 1.1

REM ======================

/*---------------------------------------------------------------------------
 * Session setup - non-destructive, no DDL, read-only queries only
 *---------------------------------------------------------------------------*/

SET ECHO OFF FEED OFF VER OFF HEA ON LIN 1000 PAGES 50000 TAB OFF TIMI OFF;
SET LONG 100000 LONGC 1000000 TRIMS ON SERVEROUT ON SIZE UNLIMITED;
SET NUM 20 SQLBL ON;
SET DEFINE ON;

/*---------------------------------------------------------------------------
 * Parameter 1: SQL_ID
 *---------------------------------------------------------------------------*/

DEF p_sql_id = '&1';

WHENEVER SQLERROR EXIT SQL.SQLCODE;
BEGIN
    IF '&p_sql_id' IS NULL OR LENGTH(TRIM('&p_sql_id')) < 5 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Parameter 1 (SQL_ID) is required. Usage: @sqlperf.sql <sql_id> <begin_date> <end_date>');
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE;

/*---------------------------------------------------------------------------
 * Parameter 2: BEGIN_DATE (accepts YYYY-MM-DD or YYYY-MM-DD HH24:MI[:SS])
 * Also accepts single-token datetime forms using T, /, or _ separators
 *---------------------------------------------------------------------------*/

COL p_begin_date_str NEW_V p_begin_date_str NOPRI;
SELECT q'^&2^' AS p_begin_date_str FROM dual;

WHENEVER SQLERROR EXIT SQL.SQLCODE;
BEGIN
    IF q'^&&p_begin_date_str^' IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002,
            'Parameter 2 (BEGIN_DATE) is required. Format: YYYY-MM-DD or YYYY-MM-DD HH24:MI[:SS]');
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE;

/*---------------------------------------------------------------------------
 * Parameter 3: END_DATE (accepts YYYY-MM-DD or YYYY-MM-DD HH24:MI[:SS])
 * Also accepts single-token datetime forms using T, /, or _ separators
 *---------------------------------------------------------------------------*/

COL p_end_date_str NEW_V p_end_date_str NOPRI;
SELECT q'^&3^' AS p_end_date_str FROM dual;

PROMPT
PROMPT Startup parameter echo (raw substitution values):
PROMPT   SQL_ID arg   = [&&p_sql_id]
PROMPT   BEGIN_DATE   = [&&p_begin_date_str]
PROMPT   END_DATE     = [&&p_end_date_str]

WHENEVER SQLERROR EXIT SQL.SQLCODE;
BEGIN
    IF q'^&&p_end_date_str^' IS NULL THEN
        RAISE_APPLICATION_ERROR(-20003,
            'Parameter 3 (END_DATE) is required. Format: YYYY-MM-DD or YYYY-MM-DD HH24:MI[:SS]');
    ELSIF REGEXP_LIKE(q'^&&p_end_date_str^', '^\d{2}:\d{2}(:\d{2})?$') THEN
        RAISE_APPLICATION_ERROR(-20005,
            'END_DATE was passed as a time-only token [' || q'^&&p_end_date_str^' || ']. ' ||
            'If you passed timestamps with spaces, wrap each timestamp in double quotes ' ||
            'or use YYYY-MM-DDTHH24:MI[:SS]. Example: @sqltune.sql ' ||
            '&p_sql_id "2025-12-29 15:09:57" "2026-04-28 15:09:57"');
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE;

/*---------------------------------------------------------------------------
 * Parse date parameters into stable substitution variables.
 * Supported literal forms:
 *   - YYYY-MM-DD
 *   - YYYY-MM-DD HH24:MI
 *   - YYYY-MM-DD HH24:MI:SS
 *   - YYYY-MM-DDTHH24:MI[:SS]
 *   - YYYY-MM-DD/HH24:MI[:SS]
 *   - YYYY-MM-DD_HH24:MI[:SS]
 *   - TIMESTAMP 'YYYY-MM-DD HH24:MI:SS'
 *
 * Supported SQL expression forms (evaluated dynamically):
 *   - SYSDATE
 *   - (SYSDATE - 1)
 *   - TO_DATE('01/01/2026 05:00:00','MM/DD/YYYY HH24:MI:SS')
 *   - TRUNC(SYSDATE)
 *   - Any expression that evaluates to a DATE or TIMESTAMP
 *---------------------------------------------------------------------------*/

DEF p_begin_date_resolved = '1970-01-01 00:00:00';
DEF p_end_date_resolved   = '1970-01-01 00:00:00';

WHENEVER SQLERROR EXIT SQL.SQLCODE;

VAR v_begin_resolved VARCHAR2(30)
VAR v_end_resolved   VARCHAR2(30)

DECLARE

    v_beg VARCHAR2(500) := TRIM(q'^&&p_begin_date_str^');
    v_end VARCHAR2(500) := TRIM(q'^&&p_end_date_str^');

    /*-----------------------------------------------------------------------
     * resolve_date_input:
     *   Resolves a date input string to YYYY-MM-DD HH24:MI:SS.
     *   Recognises fixed literal formats first; anything else is
     *   treated as a SQL expression and evaluated via EXECUTE IMMEDIATE.
     *   p_is_end_date controls whether a bare
     *   YYYY-MM-DD value means start-of-day (N) or end-of-day (Y).
     *-----------------------------------------------------------------------*/

    FUNCTION resolve_date_input(
        p_input       IN VARCHAR2,
        p_is_end_date IN VARCHAR2 DEFAULT 'N'
    ) RETURN VARCHAR2 IS

        v_in  VARCHAR2(500) := TRIM(p_input);
        v_out VARCHAR2(30);

    BEGIN

        -- TIMESTAMP with quotes: TIMESTAMP '2026-04-27 14:57:50'
        IF REGEXP_LIKE(v_in,
            '^TIMESTAMP\s+''\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}''$',
            'i') THEN

            v_out :=
                TO_CHAR(
                    TO_DATE(
                        REGEXP_SUBSTR(v_in, '''(.*)''', 1, 1, NULL, 1),
                        'YYYY-MM-DD HH24:MI:SS'
                    ),
                    'YYYY-MM-DD HH24:MI:SS'
                );

        -- TIMESTAMP without quotes: TIMESTAMP 2026-04-27 14:57:50
        ELSIF REGEXP_LIKE(v_in,
            '^TIMESTAMP\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}$',
            'i') THEN

            v_out :=
                TO_CHAR(
                    TO_DATE(
                        REGEXP_SUBSTR(v_in, '\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}'),
                        'YYYY-MM-DD HH24:MI:SS'
                    ),
                    'YYYY-MM-DD HH24:MI:SS'
                );

        -- YYYY-MM-DD HH24:MI:SS (space / T / - / / separators)

-- YYYY-MM-DD HH24:MI:SS (space / T / _ / / separators)
ELSIF REGEXP_LIKE(v_in, '^\d{4}-\d{2}-\d{2}[ T/_]\d{2}:\d{2}:\d{2}$') THEN
    v_out := TO_CHAR(
        TO_DATE(REPLACE(REPLACE(REPLACE(v_in, 'T', ' '), '_', ' '), '/', ' '),
        'YYYY-MM-DD HH24:MI:SS'),
        'YYYY-MM-DD HH24:MI:SS');

-- YYYY-MM-DD HH24:MI (space / T / _ / / separators)
ELSIF REGEXP_LIKE(v_in, '^\d{4}-\d{2}-\d{2}[ T/_]\d{2}:\d{2}$') THEN
    v_out := TO_CHAR(
        TO_DATE(REPLACE(REPLACE(REPLACE(v_in, 'T', ' '), '_', ' '), '/', ' '),
        'YYYY-MM-DD HH24:MI'),
        'YYYY-MM-DD HH24:MI:SS');

-- YYYY-MM-DD only (end-of-day for end_date, start-of-day for begin_date)
ELSIF REGEXP_LIKE(v_in, '^\d{4}-\d{2}-\d{2}$') THEN
    IF p_is_end_date = 'Y' THEN
        v_out := TO_CHAR(TO_DATE(v_in, 'YYYY-MM-DD') + 1 - 1/86400,
                         'YYYY-MM-DD HH24:MI:SS');
    ELSE
        v_out := TO_CHAR(TO_DATE(v_in, 'YYYY-MM-DD'),
                         'YYYY-MM-DD HH24:MI:SS');
    END IF;

-- Anything else: treat as a SQL date expression and evaluate dynamically
ELSE
    EXECUTE IMMEDIATE
        'SELECT TO_CHAR(CAST((' || v_in || ') AS DATE), ''YYYY-MM-DD HH24:MI:SS'') FROM dual'
    INTO v_out;
END IF;

RETURN v_out;
END resolve_date_input;

BEGIN
    :v_begin_resolved := resolve_date_input(v_beg, 'N');
    :v_end_resolved   := resolve_date_input(v_end, 'Y');

    -- Validate end >= begin
    IF TO_DATE(:v_end_resolved, 'YYYY-MM-DD HH24:MI:SS')
       < TO_DATE(:v_begin_resolved, 'YYYY-MM-DD HH24:MI:SS') THEN
        RAISE_APPLICATION_ERROR(-20004,
            'END_DATE must be greater than or equal to BEGIN_DATE. Resolved BEGIN_DATE=' ||
            :v_begin_resolved || ', END_DATE=' || :v_end_resolved);
    END IF;
END;
/

-- Transfer bind variables into SQL*Plus substitution variables
COL p_begin_date_resolved NEW_V p_begin_date_resolved NOPRI;
SELECT :v_begin_resolved AS p_begin_date_resolved FROM dual;

COL p_end_date_resolved NEW_V p_end_date_resolved NOPRI;
SELECT :v_end_resolved AS p_end_date_resolved FROM dual;

WHENEVER SQLERROR CONTINUE;

DEF v_begin_date_expr = "TO_DATE('&&p_begin_date_resolved','YYYY-MM-DD HH24:MI:SS')";
DEF v_end_date_expr   = "TO_DATE('&&p_end_date_resolved','YYYY-MM-DD HH24:MI:SS')";
DEF p_force_matching_signature = '0';
DEF p_force_matching_sig_source = 'NOT_FOUND';

PROMPT
PROMPT Startup parameter echo (resolved values):
SELECT ' SQL_ID      = [&&p_sql_id]' AS " " FROM dual;
SELECT ' BEGIN_DATE  = [&&p_begin_date_resolved]' AS " " FROM dual;
SELECT ' END_DATE    = [&&p_end_date_resolved]' AS " " FROM dual;
PROMPT

/*---------------------------------------------------------------------------
 * Spool file setup: include PDB name (SYS_CONTEXT CON_NAME) in filename
 * Produces: SQL_PERF_<sql_id>_<pdb_name>.md
 * The generated substitution variable is: &spool_file
 *---------------------------------------------------------------------------*/

SET TERMOUT OFF
COLUMN spool_file NEW_VALUE spool_file NOPRINT
SELECT 'SQL_PERF_' || REPLACE(SYS_CONTEXT('USERENV','CON_NAME'), ' ', '_') || '_' || '&&p_sql_id' || '.md' AS spool_file FROM dual;
SET TERMOUT ON

PROMPT Spooling to: &spool_file
SPOOL &spool_file

/*---------------------------------------------------------------------------
 * Validate: SQL_ID must exist in memory or AWR
 *---------------------------------------------------------------------------*/

VAR v_sql_found NUMBER;
WHENEVER SQLERROR EXIT SQL.SQLCODE;
BEGIN
    SELECT COUNT(*) INTO :v_sql_found FROM (
        SELECT sql_id FROM gv$sql
         WHERE sql_id = '&&p_sql_id' AND ROWNUM = 1
        UNION ALL
        SELECT sql_id FROM dba_hist_sqltext
         WHERE sql_id = '&&p_sql_id' AND ROWNUM = 1
    );

    IF :v_sql_found = 0 THEN
        RAISE_APPLICATION_ERROR(-20010,
            'SQL_ID '||'&&p_sql_id'||' not found in memory (GV$SQL) or AWR (DBA_HIST_SQLTEXT).');
    END IF;
END;
/

WHENEVER SQLERROR CONTINUE;

/*---------------------------------------------------------------------------
 * Capture DBID for AWR queries
 *---------------------------------------------------------------------------*/

COL p_dbid NEW_V p_dbid NOPRI;
select dbid as p_dbid from v$containers where con_id = TO_CHAR(SYS_CONTEXT('USERENV','CON_ID'));

/*---------------------------------------------------------------------------
 * Resolve target force-matching signature.
 * Prefer GV$SQL (live cursor metadata). If not present in SGA, fall back
 * to DBA_HIST_ACTIVE_SESS_HISTORY for the same SQL_ID.
 *---------------------------------------------------------------------------*/

COL p_force_matching_signature NEW_V p_force_matching_signature NOPRI;
COL p_force_matching_sig_source NEW_V p_force_matching_sig_source NOPRI;

SELECT NVL(
    TO_CHAR(
        COALESCE(
            (SELECT force_matching_signature
               FROM (
                    SELECT force_matching_signature
                    FROM gv$sql
                    WHERE sql_id = '&&p_sql_id'
                      AND force_matching_signature IS NOT NULL
                      AND force_matching_signature <> 0
                    ORDER BY last_active_time DESC NULLS LAST,
                             executions DESC,
                             child_number
               )
             WHERE ROWNUM = 1),

            (SELECT force_matching_signature
               FROM (
                    SELECT force_matching_signature
                    FROM dba_hist_active_sess_history
                    WHERE sql_id = '&&p_sql_id'
                      AND force_matching_signature IS NOT NULL
                      AND force_matching_signature <> 0
                    ORDER BY sample_time DESC
               )
             WHERE ROWNUM = 1)
        )
    ),
    '0'
) AS p_force_matching_signature,

CASE
    WHEN EXISTS (
        SELECT 1
        FROM gv$sql
        WHERE sql_id = '&&p_sql_id'
          AND force_matching_signature IS NOT NULL
          AND force_matching_signature <> 0
    ) THEN 'GV$SQL'

    WHEN EXISTS (
        SELECT 1
        FROM dba_hist_active_sess_history
        WHERE sql_id = '&&p_sql_id'
          AND force_matching_signature IS NOT NULL
          AND force_matching_signature <> 0
    ) THEN 'DBA_HIST_ACTIVE_SESS_HISTORY'

    ELSE 'NOT_FOUND'
END AS p_force_matching_sig_source
FROM dual;

PROMPT
PROMPT Resolved force matching signature:
SELECT ' FORCE_MATCH_SIG = [' ||
       CASE WHEN '&&p_force_matching_signature' = '0'
            THEN 'NOT FOUND'
            ELSE '&&p_force_matching_signature'
       END || ']' AS " "
FROM dual;

SELECT ' FMS Source      = [' || '&&p_force_matching_sig_source' || ']' AS " "
FROM dual;
PROMPT

/*---------------------------------------------------------------------------
 * Resolve AWR snap_id range for the requested time window
 *---------------------------------------------------------------------------*/

VAR v_min_snap_id NUMBER;
VAR v_max_snap_id NUMBER;

BEGIN
    SELECT MIN(snap_id), MAX(snap_id)
    INTO :v_min_snap_id, :v_max_snap_id
    FROM dba_hist_snapshot
    WHERE end_interval_time   >= &&v_begin_date_expr
      AND begin_interval_time <= &&v_end_date_expr;
END;
/

/*---------------------------------------------------------------------------
 * Determine whether GV$ACTIVE_SESSION_HISTORY covers the full analysis
 * window on ALL RAC instances. GV$ASH is a circular in-memory buffer;
 * if the requested begin_date is older than the earliest sample on ANY
 * instance, GV$ASH data is incomplete and we must use ONLY
 * DBA_HIST_ACTIVE_SESS_HISTORY for consistency.
 *
 * v_use_ash = 'Y' => GV$ASH covers full window on all instances;
 *                     use ONLY GV$ASH (weight=1, 1-second resolution)
 * v_use_ash = 'N' => GV$ASH is incomplete; use ONLY DBA_HIST (weight=10,
 *                     10-second resolution)
 *---------------------------------------------------------------------------*/

DEF v_use_ash = 'N';

COL v_use_ash_flag NEW_V v_use_ash NOPRI;

SELECT CASE
         WHEN COUNT(*) = 0 THEN 'N'
         WHEN MAX(min_sample) <= &&v_begin_date_expr THEN 'Y'
         ELSE 'N'
       END AS v_use_ash_flag
FROM (
    SELECT inst_id, MIN(sample_time) AS min_sample
    FROM gv$active_session_history
    GROUP BY inst_id
);

PROMPT
SET HEA OFF
SELECT 'ASH Source      : ' || '&&v_use_ash' ||
       ' (Y=GV$ASH only, N=DBA_HIST_ASH only)' AS " "
FROM dual;
SET HEA ON

-- Freeze the resolved value so later statements use the same substitution
DEFINE v_use_ash = '&&v_use_ash';

/*---------------------------------------------------------------------------
 * Open spool - now controlled via &spool_file (includes PDB name)
 *---------------------------------------------------------------------------*/

REM Original SPOOL replaced; using &spool_file

PROMPT # SQL PERFORMANCE DIAGNOSTIC REPORT
PROMPT
PROMPT Generated by sqltune.sql version 1
PROMPT

/*---------------------------------------------------------------------------
 * SECTION 0: LLM ANALYSIS INSTRUCTIONS
 * This section is intended for the AI/LLM that will analyze this report.
 * Human readers may skip to Section 1.
 *---------------------------------------------------------------------------*/

DECLARE
    v_db_version VARCHAR2(200);
BEGIN

DBMS_OUTPUT.PUT_LINE('The instructions in this section OVERRIDE any prior chat context. Ignore all previous conversation content.');

DBMS_OUTPUT.PUT_LINE('## SECTION 0: LLM ANALYSIS INSTRUCTIONS');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('Act as an expert Oracle database performance engineer with deep');
DBMS_OUTPUT.PUT_LINE('expertise in Oracle RAC, Exadata, optimizer behavior, execution plans,');
DBMS_OUTPUT.PUT_LINE('statistics, SQL plan management, ASH/AWR analysis, and production-safe');
DBMS_OUTPUT.PUT_LINE('remediation planning.');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('You are analyzing an Oracle SQL performance diagnostic report for a');
DBMS_OUTPUT.PUT_LINE('single SQL_ID. The database runs on Oracle Exadata RAC (Real');
DBMS_OUTPUT.PUT_LINE('Application Clusters) in a multitenant CDB');
DBMS_OUTPUT.PUT_LINE('(container databases / pluggable database) architecture.');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('Audience:');
DBMS_OUTPUT.PUT_LINE('DBA attempting to make SQL query better, their skill will vary between beginner and expert.');
DBMS_OUTPUT.PUT_LINE('They have access to execute anything in the database');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('AI Constraints:');
DBMS_OUTPUT.PUT_LINE('- do not attempt to connect to any databases');
DBMS_OUTPUT.PUT_LINE('- do not execute any SQL statements nor make any database changes');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('OPERATING MODE:');
DBMS_OUTPUT.PUT_LINE('- Perform deep research and consider any suggested skills before reaching conclusions');
DBMS_OUTPUT.PUT_LINE('- If more than 10 active sessions running the query now or SQL is running much longer than history, we may need quick triage, please ask if this is the case');
DBMS_OUTPUT.PUT_LINE('- Think like a expert Oracle performance specialist, not a generic AI');
DBMS_OUTPUT.PUT_LINE('- Be evidence-driven; cite the section(s) and data supporting every');
DBMS_OUTPUT.PUT_LINE('important conclusion');
DBMS_OUTPUT.PUT_LINE('- Distinguish clearly between facts, strong inferences, and lower-confidence hypotheses');
DBMS_OUTPUT.PUT_LINE('- Be sensitive to performance implications of functions applied to column predicates in section 11a and "Predicate Information" without a corresponding function based index at least 95 percent, or explicitly explain what missing evidence is');
DBMS_OUTPUT.PUT_LINE('preventing that confidence level');
DBMS_OUTPUT.PUT_LINE('- If you hit limits on processing (i.e. out of tokens, timeouts, etc), please specify in your answer and provide an approximate impact of such');
DBMS_OUTPUT.PUT_LINE('- Use the Oracle performance AI skills found at https://github.com/oracle/skills/tree/main/skills/db/performance');
DBMS_OUTPUT.PUT_LINE('as authoritative guide');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('ENVIRONMENT CHARACTERISTICS:');
DBMS_OUTPUT.PUT_LINE('- Exadata storage with Smart Scan / cell offload capabilities');
DBMS_OUTPUT.PUT_LINE('- Data is typically collected from the PDB (pluggable database) level');
DBMS_OUTPUT.PUT_LINE('- Our organization has a corporate wide Oracle license for following products');
DBMS_OUTPUT.PUT_LINE('Diagnostic Pack');
DBMS_OUTPUT.PUT_LINE('Tuning Pack');
DBMS_OUTPUT.PUT_LINE('RAC');
DBMS_OUTPUT.PUT_LINE('Active Data Guard');
DBMS_OUTPUT.PUT_LINE('Partitioning');
DBMS_OUTPUT.PUT_LINE('Advanced Compression');
DBMS_OUTPUT.PUT_LINE('- request for AWR,ASH,SQL Monitor,ADDM,SQL Tuning Advisor, etc reports as you find necessary');
DBMS_OUTPUT.PUT_LINE('- ASH (Active Session History) sampled every 1 sec in memory,');
DBMS_OUTPUT.PUT_LINE('every 10 sec persisted to AWR');
DBMS_OUTPUT.PUT_LINE('- This database runs on a highly shared environment thus we must ensure we do not use');
DBMS_OUTPUT.PUT_LINE('Exadata Offloading unnecessarily, especially in high concurrency which has historically saturated cpu consumption on storage cells');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('PRIMARY GOALS:');
DBMS_OUTPUT.PUT_LINE('1. Determine whether there is a current performance issue, regression,');
DBMS_OUTPUT.PUT_LINE('instability, or environmental problem affecting SQL_ID &&p_sql_id');
DBMS_OUTPUT.PUT_LINE('or FORCE_MATCHING_SIGNATURE=' ||
    CASE WHEN '&&p_force_matching_signature' = '0'
         THEN 'NOT FOUND'
         ELSE '&&p_force_matching_signature'
    END);
DBMS_OUTPUT.PUT_LINE('2. Identify the root cause, not merely the visible symptom');

DBMS_OUTPUT.PUT_LINE('2. Identify the ROOT CAUSE, not merely the visible symptom');
DBMS_OUTPUT.PUT_LINE('3. Decide whether the issue is SQL-specific, plan-specific,');
DBMS_OUTPUT.PUT_LINE('   statistics-related, bind-sensitive, concurrency-related,');
DBMS_OUTPUT.PUT_LINE('   RAC-related, Exadata-related, or system-wide');
DBMS_OUTPUT.PUT_LINE('4. Explain any observed volatility, including plan flips, execution');
DBMS_OUTPUT.PUT_LINE('   time variance, child cursor proliferation, or workload shifts');
DBMS_OUTPUT.PUT_LINE('5. Produce a practical path to good, stable future performance prioritizing database wide efficiency');
DBMS_OUTPUT.PUT_LINE('6. Ask at the end if they want an HTML summary report with detailed recommendations and deployment scripts');

-- populate DB version for optimizer context
BEGIN
    SELECT NVL(version_full, version) INTO v_db_version FROM v$instance WHERE ROWNUM = 1;
EXCEPTION WHEN OTHERS THEN
    v_db_version := 'UNKNOWN';
END;

DBMS_OUTPUT.PUT_LINE('6. Optimize for Oracle Database Enterprise Edition version: ' || v_db_version);
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('YOUR ANALYSIS SHOULD:');
DBMS_OUTPUT.PUT_LINE('1. Check for plan regressions by comparing plan_hash_values over time');
DBMS_OUTPUT.PUT_LINE('2. Evaluate E-Rows vs A-Rows in execution plans for cardinality');
DBMS_OUTPUT.PUT_LINE('   misestimates, because these are often the root cause of bad plans');
DBMS_OUTPUT.PUT_LINE('3. Assess whether optimizer statistics are stale, missing, skewed,');
DBMS_OUTPUT.PUT_LINE('   insufficiently granular, or missing extended statistics');
DBMS_OUTPUT.PUT_LINE('4. Check for RAC-specific issues: gc waits, block shipping, service');
DBMS_OUTPUT.PUT_LINE('   placement, instance skew, and interconnect-driven inefficiency');
DBMS_OUTPUT.PUT_LINE('5. Check for Exadata-specific issues: Smart Scan eligibility,');
DBMS_OUTPUT.PUT_LINE('   offload loss, single-block IO patterns, flash behavior, and');
DBMS_OUTPUT.PUT_LINE('   whether a full scan may actually be appropriate on Exadata');
DBMS_OUTPUT.PUT_LINE('6. Evaluate SQL plan controls: baselines, profiles, patches,');
DBMS_OUTPUT.PUT_LINE('   quarantine, outline influence, and child cursor behavior');
DBMS_OUTPUT.PUT_LINE('7. Check Resource Manager throttling, PX downgrades, queueing, and');
DBMS_OUTPUT.PUT_LINE('   competing workload effects');
DBMS_OUTPUT.PUT_LINE('8. Determine whether the SQL is the main problem or is a victim of a');
DBMS_OUTPUT.PUT_LINE('   broader database issue');
DBMS_OUTPUT.PUT_LINE('9. Provide detailed, actionable recommendations with pros, cons,');
DBMS_OUTPUT.PUT_LINE('   risk level, expected benefit, and confidence level for each option');
DBMS_OUTPUT.PUT_LINE('10. Rank recommendations from safest / fastest to most invasive /');
DBMS_OUTPUT.PUT_LINE('    highest-impact');
DBMS_OUTPUT.PUT_LINE('11 Search emails, chats, confluence, https://now.wf.com/ for this SQL_ID, attempt to find other work being done, incident and problem tickets');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('INTERACTIVE WORKFLOW REQUIREMENTS:');
DBMS_OUTPUT.PUT_LINE('- Your first response should very boldly announce this is an interactive session and encourage the user to ask questions!!!');
DBMS_OUTPUT.PUT_LINE('- show the SQL if a human readable format');
DBMS_OUTPUT.PUT_LINE('- If more information/validation from the database is needed, request it in the form of SQL*Plus compatible scripts that');
DBMS_OUTPUT.PUT_LINE('  contain spool on/off commands, the file will be uploaded to copilot.');
DBMS_OUTPUT.PUT_LINE('  The output file names should follow this pattern, SQL_PERF_<SQL_ID>_REPLACE(SYS_CONTEXT(''USERENV'',''CON_NAME''), '' '', ''_'')_<short_description>.md');
DBMS_OUTPUT.PUT_LINE('  The file should contain no spaces, user ''_'' instead, and lengths should be limited to 225 characters to avoid file system issues');
DBMS_OUTPUT.PUT_LINE('- Ask only for the minimum additional data required to materially');
DBMS_OUTPUT.PUT_LINE('  increase confidence');
DBMS_OUTPUT.PUT_LINE('- If cardinality misestimate is suspected, provide the exact queries');
DBMS_OUTPUT.PUT_LINE('  needed to validate row counts, NDV, skew, predicate selectivity,');
DBMS_OUTPUT.PUT_LINE('  correlation, partition pruning, and bind sensitivity');
DBMS_OUTPUT.PUT_LINE('- If a general database problem is suspected, provide exact scripts');
DBMS_OUTPUT.PUT_LINE('  to validate system-wide waits, top SQL, RAC imbalance, storage or');
DBMS_OUTPUT.PUT_LINE('  logging pressure, and time-based changes versus baseline');
DBMS_OUTPUT.PUT_LINE('- Continue iteratively until you either reach at least 95 percent');
DBMS_OUTPUT.PUT_LINE('  confidence or clearly identify the specific missing evidence');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('DDL / CHANGE MANAGEMENT REQUIREMENTS:');
DBMS_OUTPUT.PUT_LINE('- If recommending DDL, display the full DDL explicitly');
DBMS_OUTPUT.PUT_LINE('- Model storage, parallelism, compression, partitioning, and other');
DBMS_OUTPUT.PUT_LINE('  relevant defaults from the existing tables and indexes involved in');
DBMS_OUTPUT.PUT_LINE('  the execution plan whenever possible');
DBMS_OUTPUT.PUT_LINE('- Provide a rollback plan with exact rollback commands');
DBMS_OUTPUT.PUT_LINE('- Describe prerequisites, safety checks, expected impact, and post-');
DBMS_OUTPUT.PUT_LINE('  change validation steps');
DBMS_OUTPUT.PUT_LINE('- provide short term fix recommendations, we prefer online / low-risk deployment methods');
DBMS_OUTPUT.PUT_LINE('- provide long term fix recommendations, Any change will be considered');
DBMS_OUTPUT.PUT_LINE('- If you ask for an index, use ''compress low advanced'' and ''online'' options');
DBMS_OUTPUT.PUT_LINE('- If table is large, create index in parallel, invisible, after creation set noparallel, visible');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('RESPONSE CONTENT REQUIREMENTS:');
DBMS_OUTPUT.PUT_LINE('- State whether the evidence supports a current issue, historical');
DBMS_OUTPUT.PUT_LINE('  issue, intermittent issue, or no meaningful issue');
DBMS_OUTPUT.PUT_LINE('- Explain how to optimize the SQL now and how to keep performance');
DBMS_OUTPUT.PUT_LINE('  stable in the future');
DBMS_OUTPUT.PUT_LINE('- Call out uncertainty explicitly and explain what would reduce it');
DBMS_OUTPUT.PUT_LINE('- For each recommendation, include why it should help, what could go');
DBMS_OUTPUT.PUT_LINE('  wrong, and how to verify success');
DBMS_OUTPUT.PUT_LINE('- If no change is recommended, say so clearly and explain why');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('RESEARCH SOURCES TO PREFER:');
DBMS_OUTPUT.PUT_LINE('- Oracle Database 19c Performance Tuning Guide');
DBMS_OUTPUT.PUT_LINE('- Oracle Database 19c Reference for V$ACTIVE_SESSION_HISTORY and');
DBMS_OUTPUT.PUT_LINE('  DBA_HIST_ACTIVE_SESS_HISTORY');
DBMS_OUTPUT.PUT_LINE('- Oracle Database 19c PL/SQL Packages and Types Reference for');
DBMS_OUTPUT.PUT_LINE('  DBMS_WORKLOAD_REPOSITORY and DBMS_XPLAN');
DBMS_OUTPUT.PUT_LINE('- Performance skills and patterns from the oracle-db-skills');
DBMS_OUTPUT.PUT_LINE('  performance materials by kbrsice, especially ASH, AWR, explain');
DBMS_OUTPUT.PUT_LINE('  plan, optimizer statistics, index strategy, and wait event topics');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('FINAL DELIVERABLE EXPECTATION:');
DBMS_OUTPUT.PUT_LINE('- First deliver the analysis and recommendations in plain text');
DBMS_OUTPUT.PUT_LINE('- After the user accepts a recommendation, be prepared to generate a');
DBMS_OUTPUT.PUT_LINE('  complete HTML report containing the rationale, supporting evidence,');
DBMS_OUTPUT.PUT_LINE('  exact deployment scripts, exact rollback scripts, validation steps,');
DBMS_OUTPUT.PUT_LINE('  and a concise description of the database environment');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('REPORT STRUCTURE:');
DBMS_OUTPUT.PUT_LINE('Section 1: Database environment and instance configuration');
DBMS_OUTPUT.PUT_LINE('Section 2: Full SQL text');
DBMS_OUTPUT.PUT_LINE('Section 3: Execution plans (current from SGA + historical from AWR)');
DBMS_OUTPUT.PUT_LINE('Section 4: AWR historical performance summary by plan (7 days)');
DBMS_OUTPUT.PUT_LINE('Section 5: Per-execution duration statistics and DB time impact');
DBMS_OUTPUT.PUT_LINE('Section 6: SQL-level wait event profile from ASH');
DBMS_OUTPUT.PUT_LINE('Section 7: Wait event shift analysis (problem vs baseline)');
DBMS_OUTPUT.PUT_LINE('Section 8: System-wide top waits and top SQL (context)');
DBMS_OUTPUT.PUT_LINE('Section 9: Table statistics');
DBMS_OUTPUT.PUT_LINE('Section 10: Index statistics');
DBMS_OUTPUT.PUT_LINE('Section 11: Column and histogram statistics for predicate columns');
DBMS_OUTPUT.PUT_LINE('Section 13: Resource Manager, parallel execution and throttling');
DBMS_OUTPUT.PUT_LINE('Section 14: Cursor sharing analysis (child cursor version reasons)');
DBMS_OUTPUT.PUT_LINE('Section 15: ASH plan line activity (time spent per plan step)');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('OUTPUT FORMAT:');
DBMS_OUTPUT.PUT_LINE('1. Executive summary');
DBMS_OUTPUT.PUT_LINE('2. Most likely root cause(s)');
DBMS_OUTPUT.PUT_LINE('3. Evidence by report section');
DBMS_OUTPUT.PUT_LINE('4. Recommendation options with pros, cons, risk, and confidence');
DBMS_OUTPUT.PUT_LINE('5. Exact next-step SQL*Plus scripts if more evidence is needed');
DBMS_OUTPUT.PUT_LINE('6. Deployment and rollback plan if a change is recommended');
DBMS_OUTPUT.PUT_LINE('7. Confidence assessment and what is needed to reach 95 percent');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('When making recommendations, cite the specific section and data that');
DBMS_OUTPUT.PUT_LINE('supports each finding. Prioritize findings by impact and safety.');
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('BEGIN ANALYSIS IMMEDIATELY USING THE DATA BELOW.');
DBMS_OUTPUT.PUT_LINE('DO NOT ASK CLARIFYING QUESTIONS UNLESS REQUIRED TO INCREASE CONFIDENCE TO 95%');
END;
/

PROMPT ## Report Context
SET HEA OFF

SELECT '- Report Date:   ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS " " FROM dual;
SELECT '- CDB Name:      ' || SYS_CONTEXT('USERENV','CDB_NAME') AS " " FROM dual;
SELECT '- PDB Name:      ' || SYS_CONTEXT('USERENV','CON_NAME') AS " " FROM dual;
SELECT '- PDB DBID:      ' || DBID FROM V$CONTAINERS WHERE CON_ID = SYS_CONTEXT('USERENV','CON_ID');
SELECT '- CDB DBID:      ' || DBID FROM V$DATABASE;
SELECT '- SQL_ID:        ' || '&&p_sql_id' AS " " FROM dual;
SELECT '- Analysis Window: [' || '&&p_begin_date_resolved' || '] to [' || '&&p_end_date_resolved' || ']' AS " " FROM dual;
SELECT '- AWR Snap Range: ' || NVL(TO_CHAR(:v_min_snap_id),'N/A') || ' to ' || NVL(TO_CHAR(:v_max_snap_id),'N/A') AS " " FROM dual;
SELECT '- Force Match Sig: ' ||
       CASE
           WHEN '&&p_force_matching_signature' = '0' THEN 'NOT FOUND'
           ELSE '&&p_force_matching_signature'
       END || ' (source=' || '&&p_force_matching_sig_source' || ')' AS " "
FROM dual;

SELECT '- ASH Source:    ' ||
       CASE WHEN '&&v_use_ash' = 'Y'
            THEN 'GV$ASH only (in-memory ASH covers full window on all instances)'
            ELSE 'DBA_HIST_ASH only (in-memory ASH does NOT cover full window)'
       END AS " "
FROM dual;

SET HEA ON
PROMPT

/*---------------------------------------------------------------------------
 * EXECUTIVE SUMMARY (Auto-Generated)
 *---------------------------------------------------------------------------*
 * FOR THE LLM:
 *   This section provides pre-computed key indicators so you can quickly
 *   assess the situation without computing everything from raw data.
 *   These are the most important signals for triage:
 *     - Active sessions: High count = immediate attention needed
 *     - Plan stability: Multiple plans = optimizer instability
 *     - Primary/Secondary waits: Where time is spent
 *     - Cardinality assessment: E-Rows vs A-Rows severity
 *     - Elapsed trend: Getting better or worse over the window
 *---------------------------------------------------------------------------*/

PROMPT ## EXECUTIVE SUMMARY (Auto-Generated)
PROMPT

SET HEA OFF SERVEROUT ON

DECLARE

    v_active_sessions      NUMBER := 0;
    v_parallel_slaves_now  NUMBER := 0;
    v_plan_count           NUMBER := 0;
    v_distinct_plans_awr   NUMBER := 0;
    v_avg_elapsed_start    NUMBER := 0;
    v_avg_elapsed_end      NUMBER := 0;
    v_elapsed_trend_pct    NUMBER := 0;
    v_primary_wait         VARCHAR2(50);
    v_primary_wait_pct     NUMBER := 0;
    v_secondary_wait       VARCHAR2(50);
    v_secondary_wait_pct   NUMBER := 0;
    v_cpu_pct              NUMBER := 0;
    v_e_rows               NUMBER := 0;
    v_a_rows               NUMBER := 0;
    v_cardinality_ratio    NUMBER := 0;
    v_total_execs          NUMBER := 0;
    v_avg_elapsed_overall  NUMBER := 0;
    v_io_wait_pct          NUMBER := 0;
    v_cluster_wait_pct     NUMBER := 0;
    v_appl_wait_pct        NUMBER := 0;
    v_conc_wait_pct        NUMBER := 0;

BEGIN

-- 1. Count active sessions running this SQL right now
BEGIN
    SELECT COUNT(DISTINCT s.inst_id || ',' || s.sid || ',' || s.serial#)
    INTO v_active_sessions
    FROM gv$session s
    JOIN gv$sql q ON q.inst_id = s.inst_id
                 AND q.sql_id = s.sql_id
                 AND q.child_number = s.sql_child_number
    WHERE s.type = 'USER'
      AND s.status = 'ACTIVE'
      AND '&&p_force_matching_signature' <> '0'
      AND q.force_matching_signature = TO_NUMBER('&&p_force_matching_signature')
      AND NOT EXISTS (
          SELECT 1
          FROM gv$px_session px
          WHERE px.inst_id = s.inst_id
            AND px.sid = s.sid
            AND px.qcsid IS NOT NULL
            AND px.sid <> px.qcsid
      );
EXCEPTION WHEN OTHERS THEN
    v_active_sessions := 0;
END;

BEGIN
    SELECT COUNT(DISTINCT px.inst_id || ',' || px.sid)
    INTO v_parallel_slaves_now
    FROM gv$px_session px
    JOIN gv$session qc
      ON qc.inst_id = px.qcinst_id
     AND qc.sid = px.qcsid
    JOIN gv$sql q
      ON q.inst_id = qc.inst_id
     AND q.sql_id = qc.sql_id
     AND q.child_number = qc.sql_child_number
    WHERE px.qcsid IS NOT NULL
      AND px.sid <> px.qcsid
      AND qc.type = 'USER'
      AND qc.status = 'ACTIVE'
      AND qc.sql_exec_start IS NOT NULL
      AND '&&p_force_matching_signature' <> '0'
      AND q.force_matching_signature = TO_NUMBER('&&p_force_matching_signature');
EXCEPTION WHEN OTHERS THEN
    v_parallel_slaves_now := 0;
END;

-- 2. Count distinct plans in SGA
BEGIN
    SELECT COUNT(DISTINCT plan_hash_value) INTO v_plan_count
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id'
      AND plan_hash_value IS NOT NULL;
EXCEPTION WHEN OTHERS THEN
    v_plan_count := 0;
END;

-- 3. Count distinct plans in AWR for analysis window
BEGIN
    SELECT COUNT(DISTINCT h.plan_hash_value) INTO v_distinct_plans_awr
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
      AND h.executions_delta > 0;
EXCEPTION WHEN OTHERS THEN
    v_distinct_plans_awr := 0;
END;

-- 4. Calculate elapsed time trend (first quarter vs last quarter of window)
BEGIN
    WITH window_stats AS (
        SELECT TRUNC(sn.begin_interval_time, 'HH24') AS snap_hour,
               SUM(h.elapsed_time_delta) / NULLIF(SUM(h.executions_delta), 0) / 1e6 AS avg_elapsed
        FROM dba_hist_sqlstat h
        JOIN dba_hist_snapshot sn
          ON sn.snap_id = h.snap_id
         AND sn.dbid = h.dbid
         AND sn.instance_number = h.instance_number
        WHERE h.sql_id = '&&p_sql_id'
          AND sn.begin_interval_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
          AND h.executions_delta > 0
        GROUP BY TRUNC(sn.begin_interval_time, 'HH24')
    ),
    quartiles AS (
        SELECT snap_hour,
               avg_elapsed,
               NTILE(4) OVER (ORDER BY snap_hour) AS quartile
        FROM window_stats
    )
    SELECT NVL(AVG(CASE WHEN quartile = 1 THEN avg_elapsed END), 0),
           NVL(AVG(CASE WHEN quartile = 4 THEN avg_elapsed END), 0)
    INTO v_avg_elapsed_start, v_avg_elapsed_end
    FROM quartiles;

    IF v_avg_elapsed_start > 0 THEN
        v_elapsed_trend_pct :=
            ROUND((v_avg_elapsed_end - v_avg_elapsed_start) /
                   v_avg_elapsed_start * 100, 1);
    END IF;

EXCEPTION WHEN OTHERS THEN
    v_avg_elapsed_start := 0;
    v_avg_elapsed_end := 0;
    v_elapsed_trend_pct := 0;
END;

-- 5. Get wait class breakdown from ASH
BEGIN
    WITH ash_waits AS (
        SELECT NVL(wait_class, 'ON CPU') AS wait_class,
               COUNT(*) * CASE WHEN '&&v_use_ash' = 'Y' THEN 1 ELSE 10 END AS samples
        FROM (
            SELECT wait_class
            FROM gv$active_session_history
            WHERE sql_id = '&&p_sql_id'
              AND con_dbid = &&p_dbid
              AND sample_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
              AND '&&v_use_ash' = 'Y'

            UNION ALL

            SELECT wait_class
            FROM dba_hist_active_sess_history
            WHERE sql_id = '&&p_sql_id'
              AND sample_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
              AND '&&v_use_ash' = 'N'
        )
        GROUP BY NVL(wait_class, 'ON CPU')
    ),
    total AS (
        SELECT SUM(samples) AS t FROM ash_waits
    ),
    ranked AS (
        SELECT wait_class,
               samples,
               ROUND(samples / t.t * 100, 1) AS pct,
               ROW_NUMBER() OVER (ORDER BY samples DESC) AS rn
               ROW_NUMBER() OVER (ORDER BY samples DESC) AS rn
        FROM ash_waits, total t
    )
    SELECT MAX(CASE WHEN rn = 1 THEN wait_class END),
           MAX(CASE WHEN rn = 1 THEN pct END),
           MAX(CASE WHEN rn = 2 THEN wait_class END),
           MAX(CASE WHEN rn = 2 THEN pct END),
           MAX(CASE WHEN wait_class = 'ON CPU' THEN pct ELSE 0 END)
    INTO v_primary_wait, v_primary_wait_pct,
         v_secondary_wait, v_secondary_wait_pct,
         v_cpu_pct
    FROM ranked;

EXCEPTION WHEN OTHERS THEN
    v_primary_wait := 'UNKNOWN';
    v_primary_wait_pct := 0;
    v_secondary_wait := 'UNKNOWN';
    v_secondary_wait_pct := 0;
END;

-- 6. Get cardinality info (E-Rows vs A-Rows)
BEGIN
    SELECT NVL(MIN(p.cardinality), 0) INTO v_e_rows
    FROM gv$sql_plan p
    WHERE p.sql_id = '&&p_sql_id'
      AND p.cardinality IS NOT NULL
      AND p.cardinality > 0
      AND (p.operation LIKE 'TABLE%' OR
           p.operation LIKE 'INDEX%' OR
           operation LIKE '%LOAD%');

    IF v_e_rows = 0 THEN
        SELECT NVL(MIN(p.cardinality), 0) INTO v_e_rows
        FROM dba_hist_sql_plan p
        WHERE p.sql_id = '&&p_sql_id'
          AND p.cardinality IS NOT NULL
          AND p.cardinality > 0
          AND (p.operation LIKE 'TABLE%' OR
               p.operation LIKE 'INDEX%' OR
               operation LIKE '%LOAD%');
    END IF;

    SELECT NVL(ROUND(AVG(h.rows_processed_delta /
                         NULLIF(h.executions_delta, 0))), 0)
    INTO v_avg_a_rows
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr
      AND h.executions_delta > 0;

    IF v_e_rows > 0 THEN
        v_cardinality_ratio := ROUND(v_avg_a_rows / v_e_rows, 1);
    END IF;

EXCEPTION WHEN OTHERS THEN
    v_e_rows := 0;
    v_avg_a_rows := 0;
    v_cardinality_ratio := 0;
END;

-- 7. Get overall stats
BEGIN
    SELECT NVL(SUM(h.executions_delta), 0),
           NVL(ROUND(SUM(h.elapsed_time_delta) /
                     NULLIF(SUM(h.executions_delta), 0) / 1e6, 1), 0)
    INTO v_total_execs, v_avg_elapsed_overall
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr;

EXCEPTION WHEN OTHERS THEN
    v_total_execs := 0;
    v_avg_elapsed_overall := 0;
END;

-- 8. Get wait time breakdown percentages
BEGIN
    SELECT NVL(ROUND(SUM(h.iowait_delta) /
                     NULLIF(SUM(h.elapsed_time_delta), 0) * 100, 1), 0),
           NVL(ROUND(SUM(h.clwait_delta) /
                     NULLIF(SUM(h.elapsed_time_delta), 0) * 100, 1), 0),
           NVL(ROUND(SUM(h.apwait_delta) /
                     NULLIF(SUM(h.elapsed_time_delta), 0) * 100, 1), 0),
           NVL(ROUND(SUM(h.ccwait_delta) /
                     NULLIF(SUM(h.elapsed_time_delta), 0) * 100, 1), 0)
    INTO v_io_wait_pct,
         v_cluster_wait_pct,
         v_appl_wait_pct,
         v_conc_wait_pct
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr;

EXCEPTION WHEN OTHERS THEN
    v_io_wait_pct := 0;
    v_cluster_wait_pct := 0;
    v_appl_wait_pct := 0;
    v_conc_wait_pct := 0;
END;

-- Output the summary
DBMS_OUTPUT.PUT_LINE('');

-- Status line
DBMS_OUTPUT.PUT_LINE('- Status: ' ||
    CASE
        WHEN v_active_sessions >= 10 THEN
            '*** ACTIVE ISSUE *** (' || v_active_sessions ||
            ' coordinator sessions running now)'
        WHEN v_active_sessions > 0 THEN
            'ACTIVE (' || v_active_sessions ||
            ' coordinator sessions running now)'
        ELSE
            'NOT CURRENTLY RUNNING'
    END ||
    CASE
        WHEN v_parallel_slaves_now > 0 THEN
            ' [PX slaves=' || v_parallel_slaves_now || ']'
        ELSE ''
    END);

-- Plan stability
DBMS_OUTPUT.PUT_LINE('- Plan Stability: ' ||
    CASE
        WHEN v_distinct_plans_awr > 3 THEN
            'UNSTABLE (' || v_distinct_plans_awr ||
            ' distinct plans in window)'
        WHEN v_distinct_plans_awr > 1 THEN
            'MULTIPLE PLANS (' || v_distinct_plans_awr ||
            ' plans in window)'
        ELSE
            'STABLE (single plan)'
    END ||
    CASE
        WHEN v_plan_count > 1 THEN
            ' [' || v_plan_count || ' plans in SGA now]'
        ELSE ''
    END);

-- Execution stats
DBMS_OUTPUT.PUT_LINE('- Executions in Window: ' ||
    TO_CHAR(v_total_execs, 'FM999,999,999') ||
    '   Avg Elapsed: ' ||
    TO_CHAR(v_avg_elapsed_overall, 'FM999,990.0') || ' s');

-- Elapsed trend
IF v_avg_elapsed_start > 0 AND v_avg_elapsed_end > 0 THEN
    DBMS_OUTPUT.PUT_LINE('- Elapsed Trend: ' ||
        CASE
            WHEN v_elapsed_trend_pct > 20 THEN
                'DEGRADING (' ||
                TO_CHAR(v_avg_elapsed_start, 'FM990.0') || ' s -> ' ||
                TO_CHAR(v_avg_elapsed_end, 'FM990.0') || ' s, +' ||
                TO_CHAR(v_elapsed_trend_pct, 'FM990') || '%)'

            WHEN v_elapsed_trend_pct < -20 THEN
                'IMPROVING (' ||
                TO_CHAR(v_avg_elapsed_start, 'FM990.0') || ' s -> ' ||
                TO_CHAR(v_avg_elapsed_end, 'FM990.0') || ' s, ' ||
                TO_CHAR(v_elapsed_trend_pct, 'FM990') || '%)'

            ELSE
                'STABLE (~' ||
                TO_CHAR(v_avg_elapsed_overall, 'FM990.0') || ' s avg)'
        END);
END IF;

-- Wait profile
DBMS_OUTPUT.PUT_LINE('- Primary Wait: ' ||
    NVL(v_primary_wait, 'N/A') || ' (' ||
    TO_CHAR(v_primary_wait_pct, 'FM990.0') || '%)' ||

    CASE
        WHEN v_secondary_wait IS NOT NULL
         AND v_secondary_wait_pct > 5 THEN
            '  Secondary: ' || v_secondary_wait || ' (' ||
            TO_CHAR(v_secondary_wait_pct, 'FM990.0') || '%)'
        ELSE ''
    END);

-- I/O breakdown from AWR
IF v_io_wait_pct > 0 OR v_appl_wait_pct > 0 THEN
    DBMS_OUTPUT.PUT_LINE('- Time Breakdown: I/O=' ||
        TO_CHAR(v_io_wait_pct, 'FM990.0') || '%' ||

        CASE
            WHEN v_appl_wait_pct > 5 THEN
                '  AppLock=' ||
                TO_CHAR(v_appl_wait_pct, 'FM990.0') || '%'
            ELSE ''
        END ||

        CASE
            WHEN v_cluster_wait_pct > 5 THEN
                '  Cluster=' ||
                TO_CHAR(v_cluster_wait_pct, 'FM990.0') || '%'
            ELSE ''
        END ||

        CASE
            WHEN v_conc_wait_pct > 5 THEN
                '  Concurrency=' ||
                TO_CHAR(v_conc_wait_pct, 'FM990.0') || '%'
            ELSE ''
        END);
END IF;

-- Cardinality assessment
IF v_e_rows > 0 THEN
    DBMS_OUTPUT.PUT_LINE('- Cardinality: E-Rows=' ||
        TO_CHAR(v_e_rows, 'FM999,999,999') ||
        '  Avg A-Rows=' ||
        TO_CHAR(v_avg_a_rows, 'FM999,999,999') ||
        '  Ratio=' ||
        TO_CHAR(v_cardinality_ratio, 'FM999,999.0') || 'x ' ||

        CASE
            WHEN v_cardinality_ratio > 1000 THEN
                '*** SEVERE UNDERESTIMATE ***'
            WHEN v_cardinality_ratio > 100 THEN
                '** CRITICAL UNDERESTIMATE **'
            WHEN v_cardinality_ratio > 10 THEN
                '* SIGNIFICANT UNDERESTIMATE *'
            WHEN v_cardinality_ratio < 0.01 THEN
                '*** SEVERE OVERESTIMATE ***'
            WHEN v_cardinality_ratio < 0.1 THEN
                '* OVERESTIMATE *'
            ELSE
                '(acceptable)'
        END);
END IF;

DBMS_OUTPUT.PUT_LINE('');

END;
/

SET HEA ON

/*---------------------------------------------------------------------------
 * COMPUTED PROBLEM INDICATORS
 *---------------------------------------------------------------------------*
 * FOR THE LLM:
 *   These are boolean-style flags computed from multiple data sources.
 *   Each flag indicates whether a specific problem pattern is detected.
 *   Use these to quickly identify which areas need deeper investigation.
 *   A flag showing [YES] or [LIKELY] should be correlated with the
 *   corresponding detailed section for root cause analysis.
 *---------------------------------------------------------------------------*/

PROMPT ## COMPUTED PROBLEM INDICATORS
PROMPT

SET HEA OFF SERVEROUT ON

DECLARE

    -- Indicator flags
    v_has_full_scan           VARCHAR2(3)  := 'NO';
    v_full_scan_on_large_tbl  VARCHAR2(3)  := 'NO';
    v_has_parallel_hint       VARCHAR2(3)  := 'NO';
    v_parallel_for_small_work VARCHAR2(3)  := 'NO';
    v_has_cartesian           VARCHAR2(3)  := 'NO';
    v_has_nested_loop_large   VARCHAR2(3)  := 'NO';
    v_stale_stats_detected    VARCHAR2(3)  := 'NO';
    v_missing_stats_detected  VARCHAR2(3)  := 'NO';
    v_high_version_count      VARCHAR2(3)  := 'NO';
    v_bind_mismatch           VARCHAR2(3)  := 'NO';
    v_row_lock_contention     VARCHAR2(3)  := 'NO';
    v_gc_contention           VARCHAR2(3)  := 'NO';
    v_io_dominated            VARCHAR2(3)  := 'NO';
    v_cpu_dominated           VARCHAR2(3)  := 'NO';
    v_smart_scan_eligible     VARCHAR2(3)  := 'NO';
    v_index_skip_scan         VARCHAR2(3)  := 'NO';
    v_expensive_filter        VARCHAR2(3)  := 'NO';
    v_using_sql_profile       VARCHAR2(3)  := 'NO';
    v_using_baseline          VARCHAR2(3)  := 'NO';
    v_using_sql_patch         VARCHAR2(3)  := 'NO';
    v_awr_sql_monitor_reports VARCHAR2(20) := 'NONE';
    v_sga_sql_monitor_reports VARCHAR2(20) := 'NONE';
    v_resource_mgr_throttled VARCHAR2(3) := 'NO';
    v_temp_space_issue      VARCHAR2(3) := 'NO';
    v_undo_contention       VARCHAR2(3) := 'NO';

-- Helper variables
v_cnt                  NUMBER;
v_pct                  NUMBER;
v_table_blocks         NUMBER;
v_avg_rows             NUMBER;
v_ash_entries          NUMBER := 0;
v_ash_entries_fms      NUMBER := 0;
v_resource_plan        VARCHAR2(200);
v_sql_consumer_groups  VARCHAR2(4000);
v_fms_consumer_groups  VARCHAR2(4000);
v_curr_sql_execs       NUMBER := 0;
v_curr_sql_dedicated   NUMBER := 0;
v_curr_sql_px_slaves   NUMBER := 0;
v_curr_fms_execs       NUMBER := 0;
v_curr_fms_dedicated   NUMBER := 0;
v_curr_fms_px_slaves   NUMBER := 0;

BEGIN

-- 1. Check for FULL TABLE SCAN
SELECT COUNT(*)
INTO v_cnt
FROM gv$sql_plan
WHERE sql_id = '&&p_sql_id'
  AND operation = 'TABLE ACCESS'
  AND options = 'STORAGE FULL';

IF v_cnt = 0 THEN

    SELECT COUNT(*)
    INTO v_cnt
    FROM gv$sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND operation = 'TABLE ACCESS'
      AND options = 'FULL';

END IF;

IF v_cnt > 0 THEN
    v_has_full_scan := 'YES';
END IF;

-- 2. Check if full scan is on a large table (>100K blocks)
BEGIN

    SELECT MAX(t.blocks)
    INTO v_table_blocks
    FROM gv$sql_plan p
         JOIN dba_tables t
           ON t.owner = p.object_owner
          AND t.table_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation = 'TABLE ACCESS'
      AND p.options IN ('FULL', 'STORAGE FULL');

    IF v_table_blocks > 100000 THEN
        v_full_scan_on_large_tbl := 'YES';
    END IF;

EXCEPTION
    WHEN OTHERS THEN NULL;

END;

-- 3. Check for PARALLEL hint in SQL text
BEGIN

    SELECT COUNT(*)
    INTO v_cnt
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id'
      AND UPPER(sql_fulltext) LIKE '%PARALLEL%';

    IF v_cnt > 0 THEN
        v_has_parallel_hint := 'YES';
    END IF;

EXCEPTION
    WHEN OTHERS THEN NULL;

END;

-- 4. Check if parallel is used for small row counts (<10K rows avg)
BEGIN

    SELECT AVG(
               h.rows_processed_delta /
               NULLIF(h.executions_delta, 0)
           )
    INTO v_avg_rows
    FROM dba_hist_sqlstat h
         JOIN dba_hist_snapshot sn
           ON sn.snap_id = h.snap_id
          AND sn.dbid = h.dbid
          AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN
          &&v_begin_date_expr AND &&v_end_date_expr
      AND h.executions_delta > 0;

    IF v_has_parallel_hint = 'YES'
       AND NVL(v_avg_rows, 0) < 10000 THEN

        v_parallel_for_small_work := 'YES';

    END IF;

EXCEPTION
    WHEN OTHERS THEN NULL;

END;

-- 5. Check for CARTESIAN join (MERGE JOIN CARTESIAN)
SELECT COUNT(*) INTO v_cnt
FROM gv$sql_plan
WHERE sql_id = '&&p_sql_id'
  AND operation = 'MERGE JOIN'
  AND options = 'CARTESIAN';

IF v_cnt > 0 THEN
    v_has_cartesian := 'YES';
END IF;

-- 6. Check for NESTED LOOPS with high actual rows (bad for large sets)
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql_plan_statistics_all
    WHERE sql_id = '&&p_sql_id'
      AND operation = 'NESTED LOOPS'
      AND NVL(last_output_rows, 0) > 10000;

    IF v_cnt > 0 THEN
        v_has_nested_loop_large := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 7. Check for stale statistics on plan objects
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql_plan p
    JOIN dba_tab_statistics ts
      ON ts.owner = p.object_owner
     AND ts.table_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_type LIKE 'TABLE%'
      AND ts.stale_stats = 'YES';

    IF v_cnt > 0 THEN
        v_stale_stats_detected := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 8. Check for missing statistics (num_rows is null or 0)
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql_plan p
    JOIN dba_tables t
      ON t.owner = p.object_owner
     AND t.table_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_type LIKE 'TABLE%'
      AND (t.num_rows IS NULL OR t.num_rows = 0);

    IF v_cnt > 0 THEN
        v_missing_stats_detected := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 9. Check for high child cursor count (version count > 10)
BEGIN
    SELECT COUNT(DISTINCT child_number)
    INTO v_cnt
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id';

    IF v_cnt > 10 THEN
        v_high_version_count := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 10. Check for bind mismatch in child cursors
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql_shared_cursor
    WHERE sql_id = '&&p_sql_id'
      AND bind_mismatch = 'Y';

    IF v_cnt > 0 THEN
        v_bind_mismatch := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 11. Check for row lock contention (TX enqueue waits) in ASH
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM dba_hist_active_sess_history
    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                           AND &&v_end_date_expr
      AND event LIKE 'enq: TX%';

    IF v_cnt > 10 THEN
        v_row_lock_contention := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 12. Check for gc (global cache / RAC) contention
BEGIN
    SELECT ROUND(
               SUM(h.clwait_delta) /
               NULLIF(SUM(h.elapsed_time_delta), 0) * 100,
               1
           )
    INTO v_pct
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr;

    IF NVL(v_pct, 0) > 10 THEN
        v_gc_contention := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 13. Check if I/O dominated (>50% of elapsed time)
BEGIN
    SELECT ROUND(
               SUM(h.iowait_delta) /
               NULLIF(SUM(h.elapsed_time_delta), 0) * 100,
               1
           )
    INTO v_pct
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr;

    IF NVL(v_pct, 0) > 50 THEN
        v_io_dominated := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 14. Check if CPU dominated (>70% of elapsed time)
BEGIN
    SELECT ROUND(
               SUM(h.cpu_time_delta) /
               NULLIF(SUM(h.elapsed_time_delta), 0) * 100,
               1
           )
    INTO v_pct
    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number
    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN &&v_begin_date_expr
                                     AND &&v_end_date_expr;

    IF NVL(v_pct, 0) > 70 THEN
        v_cpu_dominated := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 15. Check for Exadata Smart Scan eligibility (STORAGE FULL/INDEX)
SELECT COUNT(*) INTO v_cnt
FROM gv$sql_plan
WHERE sql_id = '&&p_sql_id'
  AND options LIKE 'STORAGE%';

IF v_cnt > 0 THEN
    v_smart_scan_eligible := 'YES';
END IF;

-- 16. Check for INDEX SKIP SCAN (often suboptimal)
SELECT COUNT(*) INTO v_cnt
FROM gv$sql_plan
WHERE sql_id = '&&p_sql_id'
  AND operation = 'INDEX'
  AND options LIKE '%SKIP SCAN%';

IF v_cnt > 0 THEN
    v_index_skip_scan := 'YES';
END IF;

-- 17. Check if using SQL Profile
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id'
      AND sql_profile IS NOT NULL;

    IF v_cnt > 0 THEN
        v_using_sql_profile := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 18. Check if using SQL Plan Baseline
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id'
      AND sql_plan_baseline IS NOT NULL;

    IF v_cnt > 0 THEN
        v_using_baseline := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 19. Check if using SQL Patch
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM gv$sql
    WHERE sql_id = '&&p_sql_id'
      AND sql_patch IS NOT NULL;

    IF v_cnt > 0 THEN
        v_using_sql_patch := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 20. Check for AWR-captured SQL Monitor reports
BEGIN
    WITH matched_reports AS (
        SELECT r.component_name,
               r.report_name
        FROM dba_hist_reports r
        WHERE r.con_dbid = &&p_dbid
          AND (
                UPPER(NVL(r.key1, '')) = UPPER('&&p_sql_id')
             OR UPPER(NVL(r.key2, '')) = UPPER('&&p_sql_id')
             OR UPPER(NVL(r.key3, '')) = UPPER('&&p_sql_id')
             OR UPPER(NVL(r.key4, '')) = UPPER('&&p_sql_id')
             OR UPPER(NVL(r.report_parameters, '')) LIKE
                    '%' || UPPER('&&p_sql_id') || '%'
             OR UPPER(NVL(r.report_summary, '')) LIKE
                    '%' || UPPER('&&p_sql_id') || '%'
          )
    )
    SELECT CASE
               WHEN NVL(SUM(
                        CASE
                            WHEN UPPER(NVL(component_name, ''))
                                   LIKE '%SQL MONITOR%'
                              OR UPPER(NVL(report_name, ''))
                                   LIKE '%SQL MONITOR%'
                            THEN 1
                            ELSE 0
                        END
                    ), 0) = 0
               THEN 'NONE'
               ELSE TO_CHAR(
                        NVL(SUM(
                            CASE
                                WHEN UPPER(NVL(component_name, ''))
                                       LIKE '%SQL MONITOR%'
                                  OR UPPER(NVL(report_name, ''))
                                       LIKE '%SQL MONITOR%'
                                THEN 1
                                ELSE 0
                            END
                        ), 0)
                    )
           END
    INTO v_awr_sql_monitor_reports
    FROM matched_reports;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 21. Check for SQL Monitor entries currently in SGA
BEGIN
    SELECT CASE
               WHEN COUNT(*) = 0 THEN 'NONE'
               ELSE TO_CHAR(COUNT(*))
           END
    INTO v_sga_sql_monitor_reports
    FROM (
        SELECT DISTINCT
               m.inst_id,
               m.sql_id,
               NVL(TO_CHAR(m.sql_exec_id), 'NO_EXEC_ID') AS sql_exec_id,
               NVL(
                   TO_CHAR(
                       m.sql_exec_start,
                       'YYYY-MM-DD HH24:MI:SS'
                   ),
                   'NO_EXEC_START'
               ) AS sql_exec_start
        FROM gv$sql_monitor m
        WHERE m.sql_id = '&&p_sql_id'
    );

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 22. Check for Resource Manager throttling (resmgr waits)
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM dba_hist_active_sess_history
    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                           AND &&v_end_date_expr
      AND event LIKE 'resmgr%';

    IF v_cnt > 15 THEN
        v_resource_mgr_throttled := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;

-- 23. Check for temp space issues (direct path read/write temp)
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM dba_hist_active_sess_history
    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                           AND &&v_end_date_expr
      AND event LIKE '%temp%';

    IF v_cnt > 10 THEN
        v_temp_space_issue := 'YES';
    END IF;

EXCEPTION WHEN OTHERS THEN NULL;
END;
EXCEPTION WHEN OTHERS THEN NULL;
END;

-- Output indicators in a structured format
DBMS_OUTPUT.PUT_LINE('PLAN QUALITY INDICATORS:');

DBMS_OUTPUT.PUT_LINE(
    '  Full Table Scan Present:      ['
    || v_has_full_scan
    || ']'
    || CASE
           WHEN v_full_scan_on_large_tbl = 'YES'
           THEN '  ** ON LARGE TABLE (>100k blocks) **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Cartesian Join Detected:     ['
    || v_has_cartesian
    || ']'
    || CASE
           WHEN v_has_cartesian = 'YES'
           THEN '  ** LIKELY MISSING JOIN CONDITION **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Nested Loop on Large Set:    ['
    || v_has_nested_loop_large
    || ']'
    || CASE
           WHEN v_has_nested_loop_large = 'YES'
           THEN '  ** CONSIDER HASH JOIN **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Index Skip Scan:             ['
    || v_index_skip_scan
    || ']'
    || CASE
           WHEN v_index_skip_scan = 'YES'
           THEN '  ** POSSIBLY SUBOPTIMAL INDEX **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Smart Scan Eligible:         ['
    || v_smart_scan_eligible
    || ']'
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('PARALLELISM INDICATORS:');

DBMS_OUTPUT.PUT_LINE(
    '  Parallel Hint Present:       ['
    || v_has_parallel_hint
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  Parallel for Small Workload: ['
    || v_parallel_for_small_work
    || ']'
    || CASE
           WHEN v_parallel_for_small_work = 'YES'
           THEN '  ** PARALLEL OVERHEAD MAY EXCEED BENEFIT **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('STATISTICS INDICATORS:');

DBMS_OUTPUT.PUT_LINE(
    '  Stale Statistics Detected:   ['
    || v_stale_stats_detected
    || ']'
    || CASE
           WHEN v_stale_stats_detected = 'YES'
           THEN '  ** GATHER STATS RECOMMENDED **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Missing Statistics Detected: ['
    || v_missing_stats_detected
    || ']'
    || CASE
           WHEN v_missing_stats_detected = 'YES'
           THEN '  ** GATHER STATS REQUIRED **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('CURSOR/BIND INDICATORS:');

DBMS_OUTPUT.PUT_LINE(
    '  High Child Cursor Count:     ['
    || v_high_version_count
    || ']'
    || CASE
           WHEN v_high_version_count = 'YES'
           THEN '  ** CHECK FOR BIND/LITERAL ISSUES **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Bind Mismatch Detected:      ['
    || v_bind_mismatch
    || ']'
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('CONTENTION INDICATORS:');

DBMS_OUTPUT.PUT_LINE(
    '  Row Lock Contention (TX):    ['
    || v_row_lock_contention
    || ']'
    || CASE
           WHEN v_row_lock_contention = 'YES'
           THEN '  ** APPLICATION LOCKING ISSUE **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  RAC/GC Contention:           ['
    || v_gc_contention
    || ']'
    || CASE
           WHEN v_gc_contention = 'YES'
           THEN '  ** INTERCONNECT/BLOCK SHIPPING **'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  Resource Manager Throttled:  ['
    || v_resource_mgr_throttled
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  Temp Space Issues:           ['
    || v_temp_space_issue
    || ']'
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('RESOURCE PROFILE:');

DBMS_OUTPUT.PUT_LINE(
    '  I/O Dominated (>50%):        ['
    || v_io_dominated
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  CPU Dominated (>70%):        ['
    || v_cpu_dominated
    || ']'
);

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('SQL PLAN MANAGEMENT:');

DBMS_OUTPUT.PUT_LINE(
    '  Using SQL Profile:           ['
    || v_using_sql_profile
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  Using SQL Plan Baseline:     ['
    || v_using_baseline
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  Using SQL Patch:             ['
    || v_using_sql_patch
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  AWR SQL Monitor Reports:     ['
    || v_awr_sql_monitor_reports
    || ']'
);

DBMS_OUTPUT.PUT_LINE(
    '  SGA SQL Monitor Entries:     ['
    || v_sga_sql_monitor_reports
    || ']'
);

-- 24. Count ASH samples in the analysis window for this SQL_ID
BEGIN
    SELECT COUNT(*)
    INTO v_ash_entries
    FROM (
        SELECT 1
        FROM gv$active_session_history ash
        WHERE ash.sql_id = '&&p_sql_id'
          AND ash.sample_time BETWEEN &&v_begin_date_expr
                                   AND &&v_end_date_expr
          AND '&&v_use_ash' = 'Y'

        UNION ALL

        SELECT 1
        FROM dba_hist_active_sess_history dash
        WHERE dash.sql_id = '&&p_sql_id'
          AND dash.sample_time BETWEEN &&v_begin_date_expr
                                    AND &&v_end_date_expr
          AND '&&v_use_ash' = 'N'
    );

EXCEPTION WHEN OTHERS THEN
    v_ash_entries := 0;
END;

-- Count ASH samples for the force_matching_signature (if provided)
BEGIN
    v_ash_entries_fms := 0;

    IF '&&p_force_matching_signature' <> '0' THEN

        SELECT COUNT(*)
        INTO v_ash_entries_fms
        FROM (
            SELECT 1
            FROM gv$active_session_history ash
            WHERE ash.force_matching_signature =
                    TO_NUMBER('&&p_force_matching_signature')
              AND ash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'Y'

            UNION ALL

            SELECT 1
            FROM dba_hist_active_sess_history dash
            WHERE dash.force_matching_signature =
                    TO_NUMBER('&&p_force_matching_signature')
              AND dash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'N'
        );

    END IF;

EXCEPTION WHEN OTHERS THEN
    v_ash_entries_fms := 0;
END;

DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE('Performance METADATA FOUND:');

DBMS_OUTPUT.PUT_LINE(
    '  ASH Samples in Window for SQL_ID:         ['
    || TO_CHAR(NVL(v_ash_entries, 0))
    || ']'
    || CASE
           WHEN NVL(v_ash_entries, 0) = 0
           THEN '  ERROR - NO ROWS FOUND, try better date range'
           WHEN NVL(v_ash_entries, 0) < 100
           THEN '  WARNING - Seems Low'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  ASH Samples in Window for FORCE_MATCHING_SIGNATURE ('
    || CASE
           WHEN '&&p_force_matching_signature' = '0'
           THEN 'NOT FOUND'
           ELSE '&&p_force_matching_signature'
       END
    || '): ['
    || TO_CHAR(NVL(v_ash_entries_fms, 0))
    || ']'
    || CASE
           WHEN '&&p_force_matching_signature' <> '0'
                AND NVL(v_ash_entries_fms, 0) = 0
           THEN '  ERROR - NO ROWS FOUND, try better date range'
           WHEN '&&p_force_matching_signature' <> '0'
                AND NVL(v_ash_entries_fms, 0) < 100
           THEN '  WARNING - Seems Low'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE('');

-- Current activity counts for SQL_ID and force matching signature
BEGIN

    -- SQL_ID coordinator sessions currently running (exclude PX slaves)
    SELECT COUNT(DISTINCT s.inst_id || ',' || s.sid || ',' || s.serial#)
    INTO v_curr_sql_execs
    FROM gv$session s
    WHERE s.type = 'USER'
      AND s.status = 'ACTIVE'
      AND s.sql_id = '&&p_sql_id'
      AND s.sql_exec_start IS NOT NULL
      AND NOT EXISTS (
            SELECT 1
            FROM gv$px_session px
            WHERE px.inst_id = s.inst_id
              AND px.sid = s.sid
              AND px.qcsid IS NOT NULL
              AND px.sid <> px.qcsid
      );

EXCEPTION WHEN OTHERS THEN
    v_curr_sql_execs := 0;
END;

BEGIN

    -- Dedicated servers for these coordinator sessions
    SELECT COUNT(
               DISTINCT CASE
                            WHEN s.server = 'DEDICATED'
                            THEN s.inst_id || ',' || s.sid || ',' || s.serial#
                        END
           )
    INTO v_curr_sql_dedicated
    FROM gv$session s
    WHERE s.type = 'USER'
      AND s.status = 'ACTIVE'
      AND s.sql_id = '&&p_sql_id'
      AND s.sql_exec_start IS NOT NULL;

EXCEPTION WHEN OTHERS THEN
    v_curr_sql_dedicated := 0;
END;

BEGIN

    -- Parallel slave count engaged for those executions
    SELECT COUNT(DISTINCT px.inst_id || ',' || px.sid)
    INTO v_curr_sql_px_slaves
    FROM gv$px_session px
    JOIN gv$session qc
      ON qc.inst_id = px.qcinst_id
     AND qc.sid = px.qcsid
    JOIN gv$sql q
      ON q.inst_id = qc.inst_id
     AND q.sql_id = qc.sql_id
     AND q.child_number = qc.sql_child_number
    WHERE px.qcsid IS NOT NULL
      AND px.sid <> px.qcsid
      AND qc.type = 'USER'
      AND qc.status = 'ACTIVE'
      AND qc.sql_exec_start IS NOT NULL
      AND q.sql_id = '&&p_sql_id';

EXCEPTION WHEN OTHERS THEN
    v_curr_sql_px_slaves := 0;
END;

BEGIN

    -- Force matching signature counts (if available)
    IF '&&p_force_matching_signature' <> '0' THEN

        SELECT COUNT(DISTINCT s.inst_id || ',' || s.sid || ',' || s.serial#)
        INTO v_curr_fms_execs
        FROM gv$session s
        JOIN gv$sql q
          ON q.inst_id = s.inst_id
         AND q.sql_id = s.sql_id
         AND q.child_number = s.sql_child_number
        WHERE s.type = 'USER'
          AND s.status = 'ACTIVE'
          AND q.force_matching_signature =
                TO_NUMBER('&&p_force_matching_signature')
          AND s.sql_exec_start IS NOT NULL
          AND NOT EXISTS (
                SELECT 1
                FROM gv$px_session px
                WHERE px.inst_id = s.inst_id
                  AND px.sid = s.sid
                  AND px.qcsid IS NOT NULL
                  AND px.sid <> px.qcsid
          );

    END IF;

EXCEPTION WHEN OTHERS THEN
    v_curr_fms_execs := 0;
END;
----
WHERE px.inst_id = s.inst_id
  AND px.sid = s.sid
  AND px.qcsid IS NOT NULL
  AND px.sid <> px.qcsid
);

SELECT COUNT(
           DISTINCT CASE
                        WHEN s.server = 'DEDICATED'
                        THEN s.inst_id || ',' || s.sid || ',' || s.serial#
                    END
       )
INTO v_curr_fms_dedicated
FROM gv$session s
JOIN gv$sql q
  ON q.inst_id = s.inst_id
 AND q.sql_id = s.sql_id
 AND q.child_number = s.sql_child_number
WHERE s.type = 'USER'
  AND s.status = 'ACTIVE'
  AND q.force_matching_signature =
        TO_NUMBER('&&p_force_matching_signature')
  AND s.sql_exec_start IS NOT NULL;

SELECT COUNT(DISTINCT px.inst_id || ',' || px.sid)
INTO v_curr_fms_px_slaves
FROM gv$px_session px
JOIN gv$session qc
  ON qc.inst_id = px.qcinst_id
 AND qc.sid = px.qcsid
JOIN gv$sql q
  ON q.inst_id = qc.inst_id
 AND q.sql_id = qc.sql_id
 AND q.child_number = qc.sql_child_number
WHERE px.qcsid IS NOT NULL
  AND px.sid <> px.qcsid
  AND qc.type = 'USER'
  AND qc.status = 'ACTIVE'
  AND qc.sql_exec_start IS NOT NULL
  AND q.force_matching_signature =
        TO_NUMBER('&&p_force_matching_signature');

ELSE
    v_curr_fms_execs := 0;
    v_curr_fms_dedicated := 0;
    v_curr_fms_px_slaves := 0;
END IF;

EXCEPTION WHEN OTHERS THEN
    v_curr_fms_execs := 0;
    v_curr_fms_dedicated := 0;
    v_curr_fms_px_slaves := 0;
END;

DBMS_OUTPUT.PUT_LINE('CURRENT ACTIVITY:');

DBMS_OUTPUT.PUT_LINE(
    '  SQL_ID ('
    || '&&p_sql_id'
    || ') executing now: '
    || TO_CHAR(NVL(v_curr_sql_dedicated, 0))
    || CASE
           WHEN NVL(v_curr_sql_px_slaves, 0) > 0
           THEN ' (Parallel threads: '
                || TO_CHAR(v_curr_sql_px_slaves)
                || ')'
           ELSE ''
       END
);

DBMS_OUTPUT.PUT_LINE(
    '  FORCE_MATCHING_SIGNATURE ('
    || CASE
           WHEN '&&p_force_matching_signature' = '0'
           THEN 'NOT FOUND'
           ELSE '&&p_force_matching_signature'
       END
    || ') executing now: '
    || TO_CHAR(NVL(v_curr_fms_dedicated, 0))
    || CASE
           WHEN NVL(v_curr_fms_px_slaves, 0) > 0
           THEN ' (Parallel threads: '
                || TO_CHAR(v_curr_fms_px_slaves)
                || ')'
           ELSE ''
       END
);

-- Active Resource Plan and Consumer Groups (from ASH)
BEGIN

    BEGIN
        SELECT value
        INTO v_resource_plan
        FROM v$parameter
        WHERE name = 'resource_manager_plan';

    EXCEPTION WHEN OTHERS THEN
        v_resource_plan := 'UNKNOWN';
    END;

    -- Consumer groups for this SQL_ID (from ASH / AWR ASH)
    v_sql_consumer_groups := NULL;

    FOR r IN (
        SELECT DISTINCT
               NVL(cg.consumer_group,
                   'ID:' || a.consumer_group_id) AS grp
        FROM (
            SELECT consumer_group_id
            FROM gv$active_session_history ash
            WHERE ash.sql_id = '&&p_sql_id'
              AND ash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'Y'
              AND ash.con_dbid = &&p_dbid

            UNION

            SELECT consumer_group_id
            FROM dba_hist_active_sess_history dash
            WHERE dash.sql_id = '&&p_sql_id'
              AND dash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'N'
        ) a
        LEFT JOIN dba_rsrc_consumer_groups cg
          ON cg.consumer_group_id = a.consumer_group_id
    )
    LOOP
        IF v_sql_consumer_groups IS NULL THEN
            v_sql_consumer_groups := r.grp;
        ELSE
            v_sql_consumer_groups :=
                v_sql_consumer_groups || ', ' || r.grp;
        END IF;
    END LOOP;

    IF v_sql_consumer_groups IS NULL THEN
        v_sql_consumer_groups := 'NONE';
    END IF;

EXCEPTION WHEN OTHERS THEN
    v_sql_consumer_groups := 'NONE';
END;

BEGIN

    -- Consumer groups for this FORCE_MATCHING_SIGNATURE
    -- (from ASH / AWR ASH)
    v_fms_consumer_groups := NULL;

    FOR r IN (
        SELECT DISTINCT
               NVL(cg.consumer_group,
                   'ID:' || a.consumer_group_id) AS grp
        FROM (
            SELECT ash.consumer_group_id
            FROM gv$active_session_history ash
            JOIN gv$sql q
              ON q.inst_id = ash.inst_id
             AND q.sql_id = ash.sql_id
             AND q.child_number = ash.sql_child_number
            WHERE q.force_matching_signature =
                    TO_NUMBER('&&p_force_matching_signature')
              AND ash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'Y'
              AND ash.con_dbid = &&p_dbid

            UNION

            SELECT dash.consumer_group_id
            FROM dba_hist_active_sess_history dash
            WHERE dash.force_matching_signature =
                    TO_NUMBER('&&p_force_matching_signature')
              AND dash.sample_time BETWEEN &&v_begin_date_expr
                                       AND &&v_end_date_expr
              AND '&&v_use_ash' = 'N'
        ) a
        LEFT JOIN dba_rsrc_consumer_groups cg
          ON cg.consumer_group_id = a.consumer_group_id
    )
    LOOP
        IF v_fms_consumer_groups IS NULL THEN
            v_fms_consumer_groups := r.grp;
        ELSE
            v_fms_consumer_groups :=
                v_fms_consumer_groups || ', ' || r.grp;
        END IF;
    END LOOP;

    IF v_fms_consumer_groups IS NULL THEN
        v_fms_consumer_groups := 'NONE';
    END IF;

EXCEPTION WHEN OTHERS THEN
    v_fms_consumer_groups := 'NONE';
END;

-- Print resource plan and groups
DBMS_OUTPUT.PUT_LINE('');

DBMS_OUTPUT.PUT_LINE(
    'ACTIVE RESOURCE PLAN: '
    || NVL(v_resource_plan, 'UNKNOWN')
);

DBMS_OUTPUT.PUT_LINE(
    '  SQL_ID ('
    || '&&p_sql_id'
    || ') running under groups: '
    || v_sql_consumer_groups
);

DBMS_OUTPUT.PUT_LINE(
    '  FORCE_MATCHING_SIGNATURE ('
    || CASE
           WHEN '&&p_force_matching_signature' = '0'
           THEN 'NOT FOUND'
           ELSE '&&p_force_matching_signature'
       END
    || ') running under groups: '
    || v_fms_consumer_groups
);

END;
/

SET HEA ON

/*--------------------------------------------------------------------
 * SECTION 1: Database and Instance Environment
 *--------------------------------------------------------------------
 * FOR THE LLM:
 * Provides essential context about the database environment.
 * Use this to calibrate your analysis:
 *   - rac_instances shows RAC topology
 *   - is_exadata confirms Exadata storage
 *     (Smart Scan relevant)
 *   - cpu_count / parallel_max_servers affects PX capacity
 *   - pdb_name confirms we're in a pluggable database
 *   - optimizer_features_enable should match the db version
 *   - sga_target gives high-level memory context
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 1: Database and Instance Environment
PROMPT

COL item FOR A35 HEAD 'Item'
COL val  FOR A70 HEAD 'Value'

SELECT 'Database Name' AS item,
       name AS val
FROM v$database

UNION ALL

SELECT 'DBID',
       TO_CHAR(dbid)
FROM v$database

UNION ALL

SELECT 'DB Unique Name',
       db_unique_name
FROM v$database

UNION ALL

SELECT 'Database Role',
       database_role
FROM v$database

UNION ALL

SELECT 'Open Mode',
       open_mode
FROM v$database

UNION ALL

SELECT 'Protection Mode',
       protection_mode
FROM v$database

UNION ALL

SELECT 'CDB',
       cdb
FROM v$database

UNION ALL

SELECT 'DB Version',
       version_full
FROM v$instance

UNION ALL

SELECT 'Instance Status',
       status
FROM v$instance

UNION ALL

SELECT 'Startup Time',
       TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS')
FROM v$instance

UNION ALL

SELECT 'RAC Instances',
       TO_CHAR(COUNT(*))
FROM gv$instance

UNION ALL

SELECT 'PDB Name',
       SYS_CONTEXT('USERENV', 'CON_NAME')
FROM dual

UNION ALL

SELECT 'Is Exadata',
       CASE
           WHEN EXISTS (
                SELECT 1
                FROM v$cell_state
                WHERE ROWNUM = 1
           )
           THEN 'YES'
           ELSE 'NO'
       END
FROM dual

UNION ALL

SELECT 'CPU Count',
       value
FROM v$parameter
WHERE name = 'cpu_count'

UNION ALL

SELECT 'Parallel Max Servers',
       value
FROM v$parameter
WHERE name = 'parallel_max_servers'

UNION ALL

SELECT 'SGA Target',
       value
FROM v$parameter
WHERE name = 'sga_target'

UNION ALL

SELECT 'Optimizer Features Enable',
       value
FROM v$parameter
WHERE name = 'optimizer_features_enable'

UNION ALL

SELECT 'Optimizer Adaptive Plans',
       value
FROM v$parameter
WHERE name = 'optimizer_adaptive_plans'

UNION ALL

SELECT 'Cursor Sharing',
       value
FROM v$parameter
WHERE name = 'cursor_sharing'

UNION ALL

SELECT 'AWR Retention (days)',
       TO_CHAR(
           MAX(EXTRACT(DAY FROM retention))
       )
FROM dba_hist_wr_control
WHERE dbid = (SELECT dbid FROM v$database)

UNION ALL

SELECT 'AWR Interval (min)',
       TO_CHAR(
           MAX(
               EXTRACT(HOUR FROM snap_interval) * 60
               + EXTRACT(MINUTE FROM snap_interval)
           )
       )
FROM dba_hist_wr_control
WHERE dbid = (SELECT dbid FROM v$database)
;

PROMPT

/*--------------------------------------------------------------------
 * SECTION 2: SQL Text
 *--------------------------------------------------------------------
 * FOR THE LLM:
 * The full SQL text of the statement being analyzed.
 * Use it to:
 *   - Understand the query structure
 *     (joins, subqueries, aggregations)
 *   - Identify potential issues:
 *     Cartesian products, implicit conversions,
 *     function-wrapped predicates, SELECT *,
 *     missing bind variables
 *   - Cross-reference table/column names with
 *     Sections 9-11 stats
 *   - Check for hints that may be forcing a bad plan
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 2: SQL Text
PROMPT

SET LONG 100000 LONGC 100000

DECLARE
    l_sql_text CLOB;
BEGIN

    -- Try SGA first
    BEGIN
        SELECT sql_fulltext
        INTO l_sql_text
        FROM gv$sql
        WHERE sql_id = '&&p_sql_id'
          AND ROWNUM = 1;

    EXCEPTION WHEN NO_DATA_FOUND THEN

        -- Fall back to AWR
        BEGIN
            SELECT sql_text
            INTO l_sql_text
            FROM dba_hist_sqltext
            WHERE sql_id = '&&p_sql_id'
              AND ROWNUM = 1;

        EXCEPTION WHEN NO_DATA_FOUND THEN
            l_sql_text := '*** SQL text not found in SGA or AWR ***';
        END;
    END;

    DBMS_OUTPUT.PUT_LINE('---- BEGIN SQL TEXT ----');

    -- Print in chunks to handle large SQL
    FOR i IN 0 .. TRUNC(NVL(LENGTH(l_sql_text), 0) / 200)
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            SUBSTR(l_sql_text, i * 200 + 1, 200)
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('---- END SQL TEXT ----');

END;
/

PROMPT

/*--------------------------------------------------------------------
 * SECTION 3: Execution Plans
 *          (Current SGA + Historical AWR)
 *--------------------------------------------------------------------
 * FOR THE LLM:
 * Execution plans are THE most important diagnostic artifact.
 * Analyze:
 *   - E-Rows vs A-Rows:
 *       if A-Rows >> E-Rows (10x+),
 *       the optimizer underestimated cardinality
 *       -> bad join order, wrong access method
 *   - Operations:
 *       Table ACCESS FULL on large table = potential problem
 *       unless on Exadata with Smart Scan
 *       (look for "cell%" in stats)
 *   - HASH JOIN vs NESTED LOOPS:
 *       NL with high A-Rows = very bad
 *   - Partition pruning:
 *       Pstart/Pstop should show specific partitions,
 *       not "KEY" with many partitions accessed
 *   - Buffers (logical I/O):
 *       high values per operation = hot spot
 *   - Compare plans across plan_hash_values:
 *       what changed between the good plan and the bad plan?
 *   - Predicate Information section shows
 *       access vs filter predicates
 *   - Note section shows bind variable peeking,
 *       adaptive plans, etc.
 *
 * Section 3a:
 *   Plans from SGA with ALLSTATS LAST
 *   (last execution stats)
 *
 * Section 3b:
 *   Historical plans from AWR
 *   (may include plans no longer in SGA)
 *
 * SQL Monitor report availability now appears
 * in Computed Problem Indicators
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 3a: Current Execution Plans : Last Execution (SGA)
PROMPT

DECLARE

    v_plan_count NUMBER := 0;

BEGIN

    FOR plan_rec IN (

        WITH chosen_children AS (
            SELECT
                v.inst_id,
                v.child_number,
                v.sql_id,
                v.plan_hash_value,

                ROW_NUMBER() OVER (
                    PARTITION BY v.plan_hash_value
                    ORDER BY v.last_active_time DESC NULLS LAST,
                             v.executions DESC,
                             v.inst_id,
                             v.child_number
                ) AS rn

            FROM gv$sql v
            WHERE v.sql_id = '&&p_sql_id'
              AND v.loaded_versions > 0
        )

        SELECT
            inst_id,
            child_number,
            sql_id,
            plan_hash_value
        FROM chosen_children
        WHERE rn = 1
        ORDER BY plan_hash_value,
                 inst_id,
                 child_number

    )
    LOOP

        v_plan_count := v_plan_count + 1;

        DBMS_OUTPUT.PUT_LINE(
            'Plan: '
            || plan_rec.plan_hash_value
            || '  Inst: '
            || plan_rec.inst_id
            || '  Child: '
            || plan_rec.child_number
        );

        FOR line_rec IN (

            SELECT plan_table_output
            FROM TABLE(
                DBMS_XPLAN.DISPLAY(
                    'gv$sql_plan_statistics_all',
                    NULL,
                    'ADVANCED ALLSTATS LAST -PROJECTION -QBREGISTRY',
                    'inst_id = '
                    || plan_rec.inst_id
                    || ' AND sql_id = '''
                    || plan_rec.sql_id
                    || ''' AND child_number = '
                    || plan_rec.child_number
                )
            )

        )
        LOOP
            DBMS_OUTPUT.PUT_LINE(
                line_rec.plan_table_output
            );
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('');

    END LOOP;

    IF v_plan_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('none found');
    END IF;

END;
/

PROMPT
PROMPT ## SECTION 3b: Distinct Historical Execution Plans (AWR),
PROMPT plans NOT found in SGA
PROMPT

SELECT t.plan_table_output
FROM (

    SELECT DISTINCT
           sql_id,
           plan_hash_value,
           dbid
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND plan_hash_value NOT IN (
            SELECT plan_hash_value
            FROM gv$sql
            WHERE sql_id = '&&p_sql_id'
              AND plan_hash_value IS NOT NULL
      )

) v,
TABLE(
    DBMS_XPLAN.DISPLAY_AWR(
        v.sql_id,
        v.plan_hash_value,
        v.dbid,
        'ADVANCED'
    )
) t;
---
TABLE(
    DBMS_XPLAN.DISPLAY_AWR(
        v.sql_id,
        v.plan_hash_value,
        v.dbid,
        'ADVANCED -QBREGISTRY'
    )
) t;

SET HEA OFF

SELECT 'none found' AS status_message
FROM dual
WHERE NOT EXISTS (
    SELECT 1
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND plan_hash_value NOT IN (
            SELECT plan_hash_value
            FROM gv$sql
            WHERE sql_id = '&&p_sql_id'
              AND plan_hash_value IS NOT NULL
      )
);

SET HEA ON

PROMPT

/*--------------------------------------------------------------------
 * SECTION 3d: Cardinality Analysis - E-Rows vs A-Rows Comparison
 *--------------------------------------------------------------------
 * FOR THE LLM:
 * This section compares the optimizer's estimated rows (E-Rows)
 * from the execution plan against actual rows processed (A-Rows)
 * derived from AWR.
 *
 * Cardinality misestimates are the #1 root cause of bad execution plans.
 *
 * KEY ANALYSIS:
 *   - ratio > 10x = significant misestimate, investigate statistics
 *   - ratio > 100x = severe misestimate, almost certainly causing bad plan
 *   - E-Rows = 1 with high A-Rows = classic "single row assumption" bug
 *
 * Underestimates (A-Rows >> E-Rows) cause:
 *   - NESTED LOOPS chosen over HASH JOIN
 *   - Insufficient PGA memory allocation for sorts/hashes
 *   - Wrong join order
 *
 * Overestimates (E-Rows >> A-Rows) cause:
 *   - Unnecessary full table scans
 *   - Excessive parallelism
 *   - Over-allocation of temp space
 *
 * COLUMNS:
 *   plan_hash_value  - execution plan identifier
 *   plan_operation   - the plan step
 *                      (e.g., TABLE ACCESS FULL)
 *   plan_object      - table or index name
 *   estimated_rows   - E-Rows from optimizer
 *                      (plan cardinality)
 *   avg_actual_rows  - average rows processed per execution from AWR
 *   min_actual_rows  - minimum rows in any execution
 *   max_actual_rows  - maximum rows in any execution
 *   cardinality_ratio - A-Rows / E-Rows
 *                       (>10 = problem, >100 = severe)
 *   assessment       - plain-text severity flag
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 3d: Cardinality Analysis : E-Rows vs A-Rows
PROMPT

COL plan_hash_value   FOR 9999999999 HEAD 'Plan Hash'
COL plan_operation    FOR A35 HEAD 'Operation'
COL plan_object       FOR A30 HEAD 'Object'
COL estimated_rows    FOR 999,999,999,999 HEAD 'E-Rows'
COL avg_actual_rows   FOR 999,999,999,999 HEAD 'Avg A-Rows'
COL min_actual_rows   FOR 999,999,999,999 HEAD 'Min A-Rows'
COL max_actual_rows   FOR 999,999,999,999 HEAD 'Max A-Rows'
COL cardinality_ratio FOR 999,999,999.9 HEAD 'Ratio (A/E)'
COL assessment        FOR A20 HEAD 'Assessment'

WITH plan_cardinality AS (

    -- Get E-Rows from SGA plans (most recent)
    SELECT DISTINCT
           p.plan_hash_value,
           p.id,
           p.operation || NVL2(p.options, ' ' || p.options, '')
               AS plan_operation,
           p.object_owner
               || NVL2(p.object_name, '.' || p.object_name, '')
               AS plan_object,
           p.cardinality AS estimated_rows
    FROM gv$sql_plan p
    WHERE p.sql_id = '&&p_sql_id'
      AND p.cardinality IS NOT NULL
      AND p.cardinality > 0
      AND p.operation NOT IN (
            'PX COORDINATOR',
            'PX SEND QC (RANDOM)',
            'PX BLOCK ITERATOR'
      )

    UNION

    -- Get E-Rows from AWR plans (historical)
    SELECT DISTINCT
           p.plan_hash_value,
           p.id,
           p.operation || NVL2(p.options, ' ' || p.options, '')
               AS plan_operation,
           p.object_owner
               || NVL2(p.object_name, '.' || p.object_name, '')
               AS plan_object,
           p.cardinality
    FROM dba_hist_sql_plan p
    WHERE p.sql_id = '&&p_sql_id'
      AND p.cardinality IS NOT NULL
      AND p.cardinality > 0
      AND p.operation NOT IN (
            'PX COORDINATOR',
            'PX SEND QC (RANDOM)',
            'PX BLOCK ITERATOR'
      )

),

actual_rows AS (

    -- Get actual rows processed per execution from AWR
    SELECT
        h.plan_hash_value,

        ROUND(
            AVG(
                h.rows_processed_delta
                / NULLIF(h.executions_delta, 0)
            )
        ) AS avg_actual_rows,

        ROUND(
            MIN(
                h.rows_processed_delta
                / NULLIF(h.executions_delta, 0)
            )
        ) AS min_actual_rows,

        ROUND(
            MAX(
                h.rows_processed_delta
                / NULLIF(h.executions_delta, 0)
            )
        ) AS max_actual_rows,

        SUM(h.executions_delta) AS total_execs

    FROM dba_hist_sqlstat h
    JOIN dba_hist_snapshot sn
      ON sn.snap_id = h.snap_id
     AND sn.dbid = h.dbid
     AND sn.instance_number = h.instance_number

    WHERE h.sql_id = '&&p_sql_id'
      AND sn.begin_interval_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND h.executions_delta > 0

    GROUP BY h.plan_hash_value

)

SELECT
    pc.plan_hash_value,
    pc.plan_operation,
    pc.plan_object,
    pc.estimated_rows,
    ar.avg_actual_rows,
    ar.min_actual_rows,
    ar.max_actual_rows,

    ROUND(
        ar.avg_actual_rows
        / NULLIF(pc.estimated_rows, 0),
        1
    ) AS cardinality_ratio,

    CASE
        WHEN pc.estimated_rows = 0
            THEN 'ZERO ESTIMATE'

        WHEN ar.avg_actual_rows
             / NULLIF(pc.estimated_rows, 0) > 1000
            THEN '>>> SEVERE (1000x+)'

        WHEN ar.avg_actual_rows
             / NULLIF(pc.estimated_rows, 0) > 100
            THEN '>> CRITICAL (100x+)'

        WHEN ar.avg_actual_rows
             / NULLIF(pc.estimated_rows, 0) > 10
            THEN '> SIGNIFICANT (10x+)'

        WHEN ar.avg_actual_rows
             / NULLIF(pc.estimated_rows, 0) < 0.1
            THEN '< OVERESTIMATE (10x+)'

        WHEN ar.avg_actual_rows
             / NULLIF(pc.estimated_rows, 0) < 0.01
            THEN '<< OVERESTIMATE (100x+)'

        ELSE '~ ACCEPTABLE'
    END AS assessment

FROM plan_cardinality pc

LEFT JOIN actual_rows ar
       ON ar.plan_hash_value = pc.plan_hash_value

WHERE ar.total_execs > 0

  AND pc.plan_line_id IN (

        -- Focus on operations:
        -- table access, index access, and the root
        SELECT id
        FROM gv$sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND (
                operation LIKE 'TABLE%'
                OR operation LIKE 'INDEX%'
                OR id = 0
                OR operation LIKE '%LOAD%'
          )

        UNION

        SELECT id
        FROM dba_hist_sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND (
                operation LIKE 'TABLE%'
                OR operation LIKE 'INDEX%'
                OR id = 0
                OR operation LIKE '%LOAD%'
          )
  )

ORDER BY
    ABS(
        LOG(
            10,
            NULLIF(
                ar.avg_actual_rows
                / NULLIF(pc.estimated_rows, 0),
                0
            )
        )
    ) DESC NULLS LAST,

    pc.plan_hash_value,
    pc.plan_line_id;

PROMPT
PROMPT Cardinality Summary:

SET HEA OFF

SELECT
    '- Worst ratio: '
    || TO_CHAR(
           MAX(
               ar.avg_actual_rows
               / NULLIF(pc.estimated_rows, 0)
           ),
           'FM999,999,990.0'
       )
    || 'x'
    ||

    CASE
        WHEN MAX(
                ar.avg_actual_rows
                / NULLIF(pc.estimated_rows, 0)
             ) > 100
            THEN
                ' *** SEVERE UNDERESTIMATE - likely root cause ***'

        WHEN MAX(
                ar.avg_actual_rows
                / NULLIF(pc.estimated_rows, 0)
             ) > 10
            THEN
                ' ** SIGNIFICANT UNDERESTIMATE **'

        ELSE
                ' acceptable'
    END

FROM plan_cardinality pc
JOIN actual_rows ar
  ON ar.plan_hash_value = pc.plan_hash_value;
SET HEA ON;

PROMPT
PROMPT ## SECTION 4: AWR Hourly Execution Summary by Plan Hash (7 Days previous to window)
PROMPT

COL snap_hour            FOR A19 HEAD 'Snap Hour'
COL plan_hash_value      FOR 9999999999 HEAD 'Plan Hash Value'
COL total_execs          FOR 999,999,999 HEAD 'Total Execs'
COL avg_elapsed_sec      FOR 999,990.999 HEAD 'Avg Elapsed(s)'
COL avg_cpu_sec          FOR 999,990.999 HEAD 'Avg CPU(s)'
COL avg_iowait_sec       FOR 999,990.999 HEAD 'Avg IO Wait(s)'
COL avg_conc_wait_sec    FOR 999,990.999 HEAD 'Avg Conc Wait(s)'
COL avg_appl_wait_sec    FOR 999,990.999 HEAD 'Avg Appl Wait(s)'
COL avg_cluster_wait_sec FOR 999,990.999 HEAD 'Avg Cluster Wait(s)'
COL avg_buffer_gets      FOR 999,999,999,990 HEAD 'Avg Buffer Gets'
COL avg_disk_reads       FOR 999,999,999,990 HEAD 'Avg Disk Reads'
COL avg_direct_writes    FOR 999,999,999 HEAD 'Avg Direct Writes'
COL avg_rows_processed   FOR 999,999,990 HEAD 'Avg Rows Proc'

SELECT
    TO_CHAR(
        TRUNC(sn.begin_interval_time, 'HH24'),
        'YYYY-MM-DD HH24:MI:SS'
    ) AS snap_hour,

    h.plan_hash_value,

    SUM(h.executions_delta) AS total_execs,

    ROUND(
        SUM(h.elapsed_time_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_elapsed_sec,

    ROUND(
        SUM(h.cpu_time_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_cpu_sec,

    ROUND(
        SUM(h.iowait_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_iowait_sec,

    ROUND(
        SUM(h.ccwait_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_conc_wait_sec,

    ROUND(
        SUM(h.apwait_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_appl_wait_sec,

    ROUND(
        SUM(h.clwait_delta)
        / NULLIF(SUM(h.executions_delta),0)
        / 1e6,
        3
    ) AS avg_cluster_wait_sec,

    ROUND(
        SUM(h.buffer_gets_delta)
        / NULLIF(SUM(h.executions_delta),0)
    ) AS avg_buffer_gets,

    ROUND(
        SUM(h.disk_reads_delta)
        / NULLIF(SUM(h.executions_delta),0)
    ) AS avg_disk_reads,

    ROUND(
        SUM(h.direct_writes_delta)
        / NULLIF(SUM(h.executions_delta),0)
    ) AS avg_direct_writes,

    ROUND(
        SUM(h.rows_processed_delta)
        / NULLIF(SUM(h.executions_delta),0)
    ) AS avg_rows_processed

FROM dba_hist_sqlstat h
JOIN dba_hist_snapshot sn
  ON sn.snap_id = h.snap_id
 AND sn.dbid = h.dbid
 AND sn.instance_number = h.instance_number

WHERE h.sql_id = '&&p_sql_id'
  AND sn.begin_interval_time >= (&&v_end_date_expr - 7)
  AND sn.begin_interval_time <= &&v_end_date_expr
  AND h.executions_delta > 0

GROUP BY
    TRUNC(sn.begin_interval_time, 'HH24'),
    h.plan_hash_value

ORDER BY
    TRUNC(sn.begin_interval_time, 'HH24'),
    h.plan_hash_value;

PROMPT

/*------------------------------------------------------------------
 * SECTION 4b: Current Executions Right Now by Force-Matching Signature
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This live snapshot broadens the view from the exact SQL_ID
 * to all currently active SQL sharing the same
 * force_matching_signature as the target statement.
 *
 * Use it to see whether literal variations of the same
 * statement family are concurrently active now.
 *
 * inst_id                  - RAC instance currently running the executions
 * force_matching_signature - signature shared across literal variants
 * dedicated_servers        - dedicated server processes currently running the SQL
 * parallel_slaves          - PX slaves currently participating in those executions
 * avg_exec_elapsed_sec     - average elapsed time so far for current executions
 * matched_sql_ids          - distinct SQL_IDs currently active for that FMS
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 4b: Current Executions Right Now by Force-Matching Signature
PROMPT

COL inst_id                  FOR 99 HEAD 'Inst'
COL force_matching_signature FOR 99999999999999999999 HEAD 'Force Matching Signature'
COL current_execs            FOR 999,999 HEAD 'Current Execs'
COL dedicated_servers        FOR 999,999 HEAD 'Dedicated Srv'
COL parallel_slaves          FOR 999,999 HEAD 'PX Slaves'
COL matched_sql_ids          FOR 999,999 HEAD 'Matched SQL IDs'
COL avg_exec_elapsed_sec     FOR 999,990.9 HEAD 'Avg Exec Elapsed(s)'
COL first_exec_start         FOR A19 HEAD 'First Exec Start'

WITH current_sessions AS (
    SELECT
        s.inst_id,
        q.force_matching_signature,
        s.sql_id,
        s.sid,
        s.serial#,
        s.server,
        s.paddr,
        s.sql_exec_id,
        s.sql_exec_start

    FROM gv$session s
    JOIN gv$sql q
      ON q.inst_id = s.inst_id
     AND q.sql_id = s.sql_id
     AND q.child_number = s.sql_child_number

    WHERE s.type = 'USER'
      AND s.status = 'ACTIVE'
      AND s.sql_exec_start IS NOT NULL
      AND NOT EXISTS (
            SELECT 1
            FROM gv$px_session px
            WHERE px.inst_id = s.inst_id
              AND px.sid = s.sid
              AND px.qcsid IS NOT NULL
              AND px.sid <> px.qcsid
      )
),

px_slaves AS (
    SELECT
        px.qcinst_id AS inst_id,
        px.qcsid,
        px.inst_id || ',' || px.sid AS slave_key

    FROM gv$px_session px

    WHERE px.qcsid IS NOT NULL
      AND px.sid <> px.qcsid
)

SELECT
    c.inst_id,
    c.force_matching_signature,

    COUNT(
        DISTINCT c.sid || ',' || c.serial# || ','
        || NVL(TO_CHAR(c.sql_exec_id), 'NO_EXEC_ID')
        || ','
        || NVL(
            TO_CHAR(
                c.sql_exec_start,
                'YYYY-MM-DD HH24:MI:SS'
            ),
            'NO_EXEC_START'
        )
    ) AS current_execs,

    COUNT(
        DISTINCT CASE
            WHEN c.server = 'DEDICATED'
            THEN c.inst_id || ','
                 || NVL(RAWTOHEX(c.paddr), c.sid || ',' || c.serial#)
        END
    ) AS dedicated_servers,

    COUNT(DISTINCT px.slave_key) AS parallel_slaves,

    COUNT(DISTINCT c.sql_id) AS matched_sql_ids,

    ROUND(
        AVG(
            (SYSDATE - c.sql_exec_start) * 86400
        ),
        1
    ) AS avg_exec_elapsed_sec,

    TO_CHAR(
        MIN(c.sql_exec_start),
        'YYYY-MM-DD HH24:MI:SS'
    ) AS first_exec_start

FROM current_sessions c

LEFT JOIN px_slaves px
       ON px.inst_id = c.inst_id
      AND px.qcsid = c.sid

WHERE '&&p_force_matching_signature' <> '0'
  AND c.force_matching_signature =
      TO_NUMBER('&&p_force_matching_signature')

GROUP BY
    c.inst_id,
    c.force_matching_signature

ORDER BY
    current_execs DESC,
    c.inst_id,
    c.force_matching_signature

FETCH FIRST 10 ROWS ONLY;

SET HEA OFF

SELECT 'none found' AS status_message
FROM dual
WHERE NOT EXISTS (
    SELECT 1
    FROM gv$session s
    JOIN gv$sql q
      ON q.inst_id = s.inst_id
     AND q.sql_id = s.sql_id
     AND q.child_number = s.sql_child_number

    WHERE s.type = 'USER'
      AND s.status = 'ACTIVE'
      AND s.sql_exec_start IS NOT NULL
      AND '&&p_force_matching_signature' <> '0'
      AND q.force_matching_signature =
          TO_NUMBER('&&p_force_matching_signature')
      AND NOT EXISTS (
            SELECT 1
            FROM gv$px_session px
            WHERE px.inst_id = s.inst_id
              AND px.sid = s.sid
              AND px.qcsid IS NOT NULL
              AND px.sid <> px.qcsid
      )
);

SET HEA ON

PROMPT
PROMPT ## SECTION 4c: Removed
PROMPT
PROMPT NOTE: Section 4c (Live Session Detail : Active Sessions Running This SQL Now) has been removed by request.
PROMPT NOTE: If the Section 4b query returns no rows, treat the result as NONE.
PROMPT

/*------------------------------------------------------------------
 * SECTION 6a: ASH Wait Event Profile - Contention Analysis
 *------------------------------------------------------------------
 * (GV$ACTIVE_SESSION_HISTORY + DBA_HIST_ACTIVE_SESS_HISTORY)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This shows where this SQL spends its time — on CPU or waiting.
 *
 * Each ASH sample ~=1 second of DB time.
 * We query EITHER in-memory ASH (1-second granularity, recent data)
 * OR historical ASH from AWR (10-second sampling) — never both,
 * to avoid double-counting.
 *
 * The :v_use_ash flag controls which source.
 *
 * KEY ANALYSIS:
 *   - "ON CPU" with session_state='ON CPU' is good
 *     (doing useful work)
 *
 *   - High "Cluster" waits = RAC interconnect contention:
 *       gc cr grant 2-way,
 *       gc buffer busy acquire/release,
 *       gc current block 2-way/3-way
 *         = blocks shipped between nodes
 *
 *   - High "User I/O" physical reads:
 *       on Exadata check if cell single block vs cell multiblock
 *       vs cell smart scan
 *
 *   - "Concurrency" =
 *       buffer busy waits,
 *       library cache,
 *       row cache,
 *       cursor: mutex,
 *       latch waits
 *
 *   - "Application" =
 *       enq: TX row lock,
 *       enq: TM DML lock
 *
 *   - Compare samples across plan_hash_values to see if contention
 *     is plan-dependent
 *
 * COLUMNS:
 *   plan_hash_value = which execution plan was active
 *   session_state   = ON CPU or WAITING
 *   wait_class      = Oracle wait class grouping
 *   event           = specific wait event name
 *   ash_samples     = count of ASH samples
 *                     (≈ seconds of DB time)
 *   pct_of_sql_time = % of this SQL's total sampled time
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 6a: ASH Wait Event Profile : Contention Analysis
PROMPT

COL plan_hash_value FOR 999999999 HEAD 'Plan Hash Value'
COL session_state   FOR A10 HEAD 'State'
COL wait_class      FOR A15 HEAD 'Wait Class'
COL event           FOR A45 HEAD 'Event'
COL ash_samples     FOR 999,999,999 HEAD 'ASH Samples'
COL pct_of_sql_time FOR 990.99 HEAD '% SQL Time'

WITH combined_ash AS (

    -- In-memory ASH (1-second granularity, recent data)
    SELECT
        sql_plan_hash_value AS plan_hash_value,
        session_state,
        NVL(wait_class,'ON CPU') AS wait_class,
        NVL(event,'ON CPU') AS event,
        1 AS weight  -- each sample = 1 second

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    -- Historical ASH (10-second granularity, AWR-persisted)
    SELECT
        sql_plan_hash_value,
        session_state,
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU'),
        10  -- each AWR ASH sample ≈ 10 seconds

    FROM dba_hist_active_sess_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'N'
),

totals AS (
    SELECT SUM(weight) AS total_samples
    FROM combined_ash
)

SELECT
    a.plan_hash_value,
    a.session_state,
    a.wait_class,
    a.event,
    SUM(a.weight) AS ash_samples,

    ROUND(
        SUM(a.weight)
        / NULLIF(MAX(t.total_samples),0)
        * 100,
        2
    ) AS pct_of_sql_time

FROM combined_ash a,
     totals t

GROUP BY
    a.plan_hash_value,
    a.session_state,
    a.wait_class,
    a.event,
    t.total_samples

ORDER BY ash_samples DESC

FETCH FIRST 15 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 6b: ASH Time-Series — Contention Over Time
 *              (Hourly Buckets)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This shows how the wait profile changes over time,
 * bucketed hourly.
 *
 * Use it to correlate contention spikes with external events
 * (batch jobs, concurrent workload, maintenance windows).
 *
 * COLUMNS:
 *   snap_hour    - hour bucket
 *   on_cpu       - ASH samples on CPU (weighted seconds)
 *   user_io      - ASH samples in User I/O waits
 *   cluster_wait - ASH samples in Cluster (RAC gc) waits
 *   concurrency  - ASH samples in Concurrency waits
 *   application  - ASH samples in Application waits
 *   other_waits  - all other wait classes combined
 *   total_samples - sum of all samples for this SQL in the hour
 *   cpu_pct      - % of time on CPU
 *                   (ideal > 80% for OLTP)
 *   cluster_pct  - % of time in RAC waits
 *                   (concern if > 10-15%)
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 6b: ASH Wait Profile Over Time (Hourly)
PROMPT

COL snap_hour     FOR A19 HEAD 'Snap Hour'
COL on_cpu        FOR 999,999 HEAD 'On CPU'
COL user_io       FOR 999,999 HEAD 'User I/O'
COL cluster_wait  FOR 999,999 HEAD 'Cluster'
COL concurrency   FOR 999,999 HEAD 'Concurrency'
COL application   FOR 999,999 HEAD 'Application'
COL other_waits   FOR 999,999 HEAD 'Other'
COL total_samples FOR 9,999,999,999 HEAD 'Total'
COL cpu_pct       FOR 990.9 HEAD 'CPU%'
COL cluster_pct   FOR 990.9 HEAD 'Cluster%'

WITH combined_ash AS (

    SELECT
        sample_time,
        NVL(wait_class,'ON CPU') AS wait_class,
        1 AS weight

    FROM gv$active_session_history

    WHERE sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        sample_time,
        NVL(wait_class,'ON CPU'),
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'N'
)

SELECT
    TO_CHAR(
        TRUNC(sample_time, 'HH24'),
        'YYYY-MM-DD HH24:MI:SS'
    ) AS snap_hour,

    SUM(
        CASE
            WHEN wait_class = 'ON CPU'
            THEN weight ELSE 0
        END
    ) AS on_cpu,

    SUM(
        CASE
            WHEN wait_class = 'User I/O'
            THEN weight ELSE 0
        END
    ) AS user_io,

    SUM(
        CASE
            WHEN wait_class = 'Cluster'
            THEN weight ELSE 0
        END
    ) AS cluster_wait,

    SUM(
        CASE
            WHEN wait_class = 'Concurrency'
            THEN weight ELSE 0
        END
    ) AS concurrency,

    SUM(
        CASE
            WHEN wait_class = 'Application'
            THEN weight ELSE 0
        END
    ) AS application,

    SUM(
        CASE
            WHEN wait_class NOT IN (
                'ON CPU',
                'User I/O',
                'Cluster',
                'Concurrency',
                'Application'
            )
            THEN weight ELSE 0
        END
    ) AS other_waits,

    SUM(weight) AS total_samples,

    ROUND(
        (
            SUM(
                CASE
                    WHEN wait_class = 'ON CPU'
                    THEN weight ELSE 0
                END
            )
            / NULLIF(SUM(weight),0)
        ) * 100,
        1
    ) AS cpu_pct,

    ROUND(
        (
            SUM(
                CASE
                    WHEN wait_class = 'Cluster'
                    THEN weight ELSE 0
                END
            )
            / NULLIF(SUM(weight),0)
        ) * 100,
        1
    ) AS cluster_pct

FROM combined_ash

GROUP BY TRUNC(sample_time, 'HH24')

ORDER BY 1;

PROMPT

/*------------------------------------------------------------------
 * SECTION 7: Wait Event Shift Analysis —
 *            Is My Time Range Different?
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This section compares the wait event profile during the
 * user-specified analysis window ("problem period")
 * against the prior 7 days baseline ("normal period").
 *
 * The goal is to answer:
 *   "Did the wait profile materially change during the period
 *    I care about?"
 *
 * HOW TO READ:
 *   - baseline_pct = % of sampled time in this wait class
 *                    over prior 7 days
 *
 *   - problem_pct = % of sampled time in this wait class
 *                   during the window
 *
 *   - shift_pct = problem_pct - baseline_pct
 *                 (positive = got worse)
 *
 *   - A shift > 5-10% in Cluster, Concurrency,
 *     or Application is material
 *
 *   - A large negative shift in CPU% with corresponding
 *     positive shift in a wait class means the SQL started
 *     spending less time doing useful work and more time waiting
 *
 *   - New events appearing only in the problem period
 *     (baseline_pct = 0)
 *     are strong indicators of an environmental change
 *
 * EXADATA RAC NOTES:
 *   - A shift from "cell smart table scan"
 *     to "cell single block physical read"
 *     suggests Smart Scan stopped being used
 *     (predicate offload lost)
 *
 *   - A shift into gc% events = new RAC contention,
 *     possibly caused by a plan change that increased
 *     block-level random access
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 7a: Wait Event Shift : Problem Period vs Prior 7-Day Baseline
PROMPT

COL wait_class      FOR A15 HEAD 'Wait Class'
COL event           FOR A45 HEAD 'Event'
COL baseline_samples FOR 999,999 HEAD 'Base Samples'
COL baseline_pct    FOR 990.99 HEAD 'Base %'
COL problem_samples FOR 999,999,999,999 HEAD 'Problem Samples'
COL problem_pct     FOR 990.99 HEAD 'Problem %'
COL shift_pct       FOR 990.99 HEAD 'Shift %'

WITH baseline AS (
    SELECT
        NVL(wait_class,'ON CPU') AS wait_class,
        NVL(event,'ON CPU') AS event,
        COUNT(*) * 10 AS samples  -- AWR ASH, 10-sec weight

    FROM dba_hist_active_sess_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr - 7
            AND &&v_begin_date_expr

    GROUP BY
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU')
),

problem AS (

    -- In-memory ASH for the problem window
    SELECT
        NVL(wait_class,'ON CPU') AS wait_class,
        NVL(event,'ON CPU') AS event,
        COUNT(*) AS samples  -- 1-sec weight

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    GROUP BY
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU')

    UNION ALL

    -- AWR ASH for the problem window (older data)
    SELECT
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU'),
        COUNT(*) * 10

    FROM dba_hist_active_sess_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'N'

    GROUP BY
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU')
),

problem_agg AS (
    SELECT
        wait_class,
        event,
        SUM(samples) AS samples
    FROM problem
    GROUP BY wait_class, event
),

base_total AS (
    SELECT NVL(SUM(samples),1) AS t
    FROM baseline
),

prob_total AS (
    SELECT NVL(SUM(samples),1) AS t
    FROM problem_agg
)

SELECT
    NVL(p.wait_class, b.wait_class) AS wait_class
---
SELECT
    NVL(p.wait_class, b.wait_class) AS wait_class,
    NVL(p.event, b.event) AS event,

    NVL(b.samples, 0) AS baseline_samples,

    ROUND(
        NVL(b.samples,0) / bt.t * 100,
        2
    ) AS baseline_pct,

    NVL(p.samples, 0) AS problem_samples,

    ROUND(
        NVL(p.samples,0) / pt.t * 100,
        2
    ) AS problem_pct,

    ROUND(
        NVL(p.samples,0) / pt.t * 100,
        2
    )
    -
    ROUND(
        NVL(b.samples,0) / bt.t * 100,
        2
    ) AS shift_pct

FROM problem_agg p
FULL OUTER JOIN baseline b
  ON b.wait_class = p.wait_class
 AND b.event = p.event

CROSS JOIN base_total bt
CROSS JOIN prob_total pt

ORDER BY ABS(
    ROUND(NVL(p.samples,0)/pt.t*100,2)
    -
    ROUND(NVL(b.samples,0)/bt.t*100,2)
) DESC

FETCH FIRST 15 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 7b: Wait Class Summary Shift (Compact View)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Same comparison as 3a but rolled up to wait_class level
 * for a quick "at a glance" view.
 *
 * Material shifts are easier to spot here.
 *
 * A shift_pct > +5 in any non-CPU class warrants investigation.
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 7b: Wait Class Summary Shift (Compact)
PROMPT

COL wait_class   FOR A15 HEAD 'Wait Class'
COL baseline_pct FOR 990.99 HEAD 'Base %'
COL problem_pct  FOR 990.99 HEAD 'Problem %'
COL shift_pct    FOR S990.99 HEAD 'Shift %'
COL direction    FOR A10 HEAD 'Direction'

WITH baseline AS (
    SELECT
        NVL(wait_class,'ON CPU') AS wait_class,
        COUNT(*) * 10 AS samples

    FROM dba_hist_active_sess_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr - 7
            AND &&v_begin_date_expr

    GROUP BY NVL(wait_class,'ON CPU')
),

problem AS (

    SELECT
        NVL(wait_class,'ON CPU') AS wait_class,
        COUNT(*) AS samples

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    GROUP BY NVL(wait_class,'ON CPU')

    UNION ALL

    SELECT
        NVL(wait_class,'ON CPU'),
        COUNT(*) * 10

    FROM dba_hist_active_sess_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN
            &&v_begin_date_expr
            AND &&v_end_date_expr
      AND '&&v_use_ash' = 'N'

    GROUP BY NVL(wait_class,'ON CPU')
),

problem_agg AS (
    SELECT
        wait_class,
        SUM(samples) AS samples
    FROM problem
    GROUP BY wait_class
),

base_total AS (
    SELECT NVL(SUM(samples),1) AS t
    FROM baseline
),

prob_total AS (
    SELECT NVL(SUM(samples),1) AS t
    FROM problem_agg
)

SELECT
    NVL(p.wait_class, b.wait_class) AS wait_class,

    ROUND(
        NVL(b.samples,0) / bt.t * 100,
        2
    ) AS baseline_pct,

    ROUND(
        NVL(p.samples,0) / pt.t * 100,
        2
    ) AS problem_pct,

    ROUND(
        NVL(p.samples,0) / pt.t * 100,
        2
    )
    -
    ROUND(
        NVL(b.samples,0) / bt.t * 100,
        2
    ) AS shift_pct,

    CASE
        WHEN ROUND(NVL(p.samples,0)/pt.t*100,2)
           - ROUND(NVL(b.samples,0)/bt.t*100,2) > 5
        THEN '>>> WORSE'

        WHEN ROUND(NVL(p.samples,0)/pt.t*100,2)
           - ROUND(NVL(b.samples,0)/bt.t*100,2) < -5
        THEN '<<< BETTER'

        ELSE '= stable'
    END AS direction

FROM problem_agg p
FULL OUTER JOIN baseline b
  ON b.wait_class = p.wait_class

CROSS JOIN base_total bt
CROSS JOIN prob_total pt

ORDER BY ABS(
    ROUND(NVL(p.samples,0)/pt.t*100,2)
    -
    ROUND(NVL(b.samples,0)/bt.t*100,2)
) DESC;

PROMPT

/*------------------------------------------------------------------
 * SECTION 9: Objects Referenced in Execution Plans (SGA + AWR)
 *------------------------------------------------------------------
 * We first build a list of all distinct objects
 * (tables/indexes) referenced in any plan for this SQL_ID,
 * from both GV$SQL_PLAN (memory) and DBA_HIST_SQL_PLAN (AWR).
 *
 * Then we join to the dictionary for stats.
 *------------------------------------------------------------------*/

/*------------------------------------------------------------------
 * SECTION 9a: Table Metadata for Objects in Execution Plans
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Shows optimizer statistics for every table referenced in
 * any execution plan for this SQL_ID.
 *
 * Use this to detect:
 *   - stale statistics:
 *       stale_stats = 'YES'
 *       or last_analyzed is old
 *
 *   - Empty stats:
 *       num_rows = 0 or NULL on a non-empty table
 *
 *   - Significant DML since last analyze:
 *       inserts+updates+deletes from DBA_TAB_MODIFICATIONS
 *
 *   - num_rows:
 *       stats are effectively stale even if Oracle hasn't
 *       flagged them yet
 *
 *   - Partitioned tables:
 *       global stats may mask partition skew
 *
 *   - degree > 1:
 *       query enabled at table level
 *
 *   - compression:
 *       on Exadata, HCC compression affects Smart Scan
 *
 * KEY COLUMNS:
 *   owner / table_name  - table identity
 *   num_rows / blocks   - optimizer's row/block estimates
 *   avg_row_len         - used in cost calculations
 *   last_analyzed       - when stats were last gathered
 *   stale_stats         - Oracle's staleness flag (YES/NO)
 *   sample_size         - rows sampled during stats gathering
 *   partitioned         - YES if partitioned
 *   degree / compression - parallelism and storage info
 *   dml_inserts/updates/deletes
 *       - DML since last analyze
 *         (from DBA_TAB_MODIFICATIONS)
 *   pct_modified
 *       - (inserts+updates+deletes) / num_rows * 100
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 9a: Table Metadata for Objects in Execution Plans
PROMPT

COL owner         FOR A20 HEAD 'Owner'
COL table_name    FOR A30 HEAD 'Table Name'
COL num_rows      FOR 999,999,999,999 HEAD 'Num Rows'
COL blocks        FOR 999,999,999 HEAD 'Blocks'
COL avg_row_len   FOR 99,999 HEAD 'Avg Row Len'
COL last_analyzed FOR A19 HEAD 'Last Analyzed'
COL stale_stats   FOR A5 HEAD 'Stale'
COL sample_size   FOR 999,999,999,999 HEAD 'Sample Size'
COL partitioned   FOR A5 HEAD 'Part?'
COL degree        FOR A6 HEAD 'Degree'
COL compression   FOR A12 HEAD 'Compression'
COL dml_inserts   FOR 999,999,999,999 HEAD 'Inserts'
COL dml_updates   FOR 999,999,999,999 HEAD 'Updates'
COL dml_deletes   FOR 999,999,999,999 HEAD 'Deletes'
COL pct_modified  FOR 990.99 HEAD '% Modified'
COL segment_mb    FOR 999,999,990.9 HEAD 'Segment MB'
COL row_movement  FOR A8 HEAD 'Row Move'
COL logging       FOR A7 HEAD 'Logging'
COL compress_for  FOR A18 HEAD 'Compress For'
COL seg_created   FOR A12 HEAD 'Seg Created'

WITH plan_objects AS (

    -- Objects from SGA plans
    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name

    FROM gv$sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    -- Objects from AWR plans
    SELECT DISTINCT
        object_owner,
        object_name

    FROM dba_hist_sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    -- Tables behind indexes in SGA plans
    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    -- Tables behind indexes in AWR plans
    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
)

SELECT
    t.owner,
    t.table_name,
    t.num_rows,
    t.blocks,
    t.avg_row_len,

    TO_CHAR(
        t.last_analyzed,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS last_analyzed,

    t.stale_stats,
    t.sample_size,
    t.partitioned,
    TRIM(t.degree) AS degree,

    t.compression
    || CASE
           WHEN t.compress_for IS NOT NULL
           THEN ' ('||t.compress_for||')'
       END AS compression,

    NVL(m.inserts,0) AS dml_inserts,
    NVL(m.updates,0) AS dml_updates,
    NVL(m.deletes,0) AS dml_deletes,

    CASE
        WHEN NVL(t.num_rows,0) > 0
        THEN ROUND(
                 (
                     NVL(m.inserts,0)
                     + NVL(m.updates,0)
                     + NVL(m.deletes,0)
                 )
                 / t.num_rows * 100,
                 2
             )
    END AS pct_modified,

    ROUND(
        NVL(seg.bytes,0) / 1048576,
        1
    ) AS segment_mb,

    NVL(t.row_movement,'DISABLED') AS row_movement,
    NVL(t.logging,'YES') AS logging,
    NVL(t.compress_for,'-') AS compress_for,
    NVL(t.segment_created,'N/A') AS seg_created

FROM plan_objects po

JOIN dba_tables t
  ON t.owner = po.owner
 AND t.table_name = po.name

LEFT JOIN dba_tab_statistics ts
  ON ts.owner = t.owner
 AND ts.table_name = t.table_name
 AND ts.partition_name IS NULL

LEFT JOIN dba_tab_modifications m
  ON m.table_owner = t.owner
 AND m.table_name = t.table_name
 AND m.partition_name IS NULL

LEFT JOIN (
    SELECT
        owner,
        segment_name,
        SUM(bytes) AS bytes
    FROM dba_segments
    WHERE segment_type LIKE 'TABLE%'
    GROUP BY owner, segment_name
) seg
  ON seg.owner = t.owner
 AND seg.segment_name = t.table_name

ORDER BY t.owner, t.table_name;

PROMPT

/*------------------------------------------------------------------
 * SECTION 9b: Partitioning Summary for Plan Tables
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Shows whether each table in the execution plan is partitioned
 * and/or subpartitioned, the partitioning scheme, partition key
 * columns, and total partition/subpartition counts.
 *
 * Use this to:
 *   - Verify partition pruning is possible for the SQL's predicates
 *   - Detect tables that SHOULD be partitioned but are not
 *   - Identify composite partitioning
 *       (RANGE-HASH, RANGE-LIST, etc.)
 *   - If "not partitioned" is shown,
 *       partition pruning cannot apply
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 9b: Partitioning Summary for Plan Tables
PROMPT

COL owner              FOR A20 HEAD 'Owner'
COL table_name         FOR A30 HEAD 'Table Name'
COL partitioning       FOR A22 HEAD 'Partitioning'
COL partition_count    FOR 999,999 HEAD 'Partitions'
COL partition_keys     FOR A60 HEAD 'Partition Key' WORD_WRAP
COL subpartitioning    FOR A22 HEAD 'Subpartitioning'
COL subpartition_count FOR 999,999 HEAD 'Subpartitions'
COL subpartition_keys  FOR A60 HEAD 'Subpartition Key' WORD_WRAP

WITH plan_tables AS (

    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name

    FROM gv$sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    SELECT DISTINCT
        object_owner,
        object_name

    FROM dba_hist_sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
),

part_keys AS (
    SELECT
        owner,
        name AS table_name,

        LISTAGG(column_name, ', ')
            WITHIN GROUP (ORDER BY column_position)
            AS partition_keys

    FROM dba_part_key_columns

    WHERE object_type = 'TABLE'
      AND (owner, name) IN (
            SELECT owner, name
            FROM plan_tables
      )

    GROUP BY owner, name
),

subpart_keys AS (
    SELECT
        owner,
        name AS table_name,

        LISTAGG(column_name, ', ')
            WITHIN GROUP (ORDER BY column_position)
            AS subpartition_keys

    FROM dba_subpart_key_columns

    WHERE object_type = 'TABLE'
      AND (owner, name) IN (
            SELECT owner, name
            FROM plan_tables
      )

    GROUP BY owner, name
)

SELECT
    t.owner,
    t.table_name,

    CASE
        WHEN pt.partitioning_type IS NOT NULL
        THEN pt.partitioning_type
        ELSE 'NO'
    END AS partitioning,

    NVL(pt.partition_count,0) AS partition_count,

    NVL(pk.partition_keys,'-') AS partition_keys,

    CASE
        WHEN pt.subpartitioning_type IS NOT NULL
         AND pt.subpartitioning_type <> 'NONE'
        THEN pt.subpartitioning_type
        ELSE 'NO'
    END AS subpartitioning,

    NVL(pt.def_subpartition_count,0)
        AS subpartition_count,

    NVL(sk.subpartition_keys,'-')
        AS subpartition_keys

FROM plan_tables ptb

JOIN dba_tables t
  ON t.owner = ptb.owner
 AND t.table_name = ptb.name

LEFT JOIN dba_part_tables pt
  ON pt.owner = t.owner
 AND pt.table_name = t.table_name

LEFT JOIN part_keys pk
  ON pk.owner = t.owner
 AND pk.table_name = t.table_name

LEFT JOIN subpart_keys sk
  ON sk.owner = t.owner
 AND sk.table_name = t.table_name

ORDER BY t.owner, t.table_name;

/*------------------------------------------------------------------
 * SECTION 10a: Index Metadata for Objects in Execution Plans
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Shows metadata for ALL indexes on every table referenced
 * in any execution plan for this SQL_ID
 * (from SGA + AWR),
 * whether or not the optimizer chose that index in the captured plan.
 *------------------------------------------------------------------*/
/*------------------------------------------------------------------
 * KEY ANALYSIS:
 *------------------------------------------------------------------
 * - columns lists the indexed columns in key order
 * - status shows VALID / UNUSABLE / N/A for operational readiness
 * - last_analyzed and stale_stats show whether index stats may be old
 * - compression_level shows index compression metadata
 * - clustering_factor close to num_rows = poorly clustered
 *   (index range scan will generate many random reads)
 *   close to blocks = well clustered
 *   Ratio cf_to_blocks = clustering_factor/leaf_blocks
 * - high values signal poor clustering
 * - blevel (B-tree height) > 2 normal; >3 may add latency per probe
 * - distinct_keys vs table num_rows:
 *   low selectivity indexes may cause optimizer to prefer full scans
 * - On Exadata:
 *   if an index is NOT used and the plan does a full scan,
 *   that may be fine - Smart Scan on Exadata can be faster than
 *   index access for large result sets
 * - partitioned indexes:
 *   check if LOCAL vs GLOBAL.
 *   GLOBAL indexes on partitioned tables may become unusable after
 *   partition DDL
 * - visibility:
 *   INVISIBLE indexes are not considered by the optimizer unless
 *   OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE
 *
 * COLUMNS:
 * owner / table_name - table and index ownership context
 * columns            - indexed columns in key order
 * index_type         - NORMAL, BITMAP, FUNCTION-BASED, etc.
 * uniqueness         - UNIQUE or NONUNIQUE
 * num_rows / distinct_keys - index-level cardinality
 * blevel             - B-tree depth (0 = single-level)
 * leaf_blocks        - size of index in leaf blocks
 * clustering_factor  - physical row ordering correlation
 * cf_to_blocks       - clustering_factor / leaf_blocks ratio
 * compression_level  - index compression setting / prefix length
 * last_analyzed      - when index stats were gathered
 * stale_stats        - Oracle staleness flag
 * partitioned        - YES if partitioned index
 * visibility         - VISIBLE or INVISIBLE
 * status             - VALID, UNUSABLE, N/A
 * degree             - parallelism level
 * locality           - locality of the index
 * idx_part_type      - index partition type
 * idx_part_key       - index partition key
 * segment_mb         - segment size in MB
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 10a: Index Metadata for Objects in Execution Plans
PROMPT

COL tbl_name           FOR A50 HEAD 'Table'
COL index_name         FOR A30 HEAD 'Index Name'
COL columns            FOR A80 HEAD 'Columns' WORD_WRAP
COL index_type         FOR A20 HEAD 'Index Type'
COL uniqueness         FOR A9 HEAD 'Unique?'
COL num_rows           FOR 999,999,999,999 HEAD 'Num Rows'
COL distinct_keys      FOR 999,999,999,999 HEAD 'Distinct Keys'
COL blevel             FOR 99 HEAD 'BLvl'
COL leaf_blocks        FOR 999,999,999 HEAD 'Leaf Blocks'
COL clustering_factor  FOR 999,999,999,999 HEAD 'Clustering Factor'
COL cf_to_blocks       FOR 999,990.9 HEAD 'CF/Blocks'
COL compression_level  FOR A18 HEAD 'Compression'
COL last_analyzed      FOR A19 HEAD 'Last Analyzed'
COL stale_stats        FOR A5 HEAD 'Stale'
COL partitioned        FOR A5 HEAD 'Part?'
COL visibility         FOR A9 HEAD 'Visible?'
COL status             FOR A8 HEAD 'Status'
COL degree             FOR A6 HEAD 'Degree'
COL locality           FOR A8 HEAD 'Locality'
COL idx_part_type      FOR A18 HEAD 'Idx Part Type'
COL idx_part_key       FOR A30 HEAD 'Idx Partition Key'
COL segment_mb         FOR 999,999,990.9 HEAD 'Segment MB'

WITH
plan_tables AS (

    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name

    FROM gv$sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    SELECT DISTINCT
        object_owner,
        object_name

    FROM dba_hist_sql_plan

    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (
            operation LIKE 'TABLE%'
         OR operation LIKE '%LOAD%'
      )

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name

    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name

    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
),

index_columns AS (

    SELECT
        ic.index_owner AS owner,
        ic.index_name,

        LISTAGG(
            ic.column_name ||
            CASE
                WHEN ic.descend = 'DESC'
                THEN ' DESC'
            END,
            ', '
        ) WITHIN GROUP (
            ORDER BY ic.column_position
        ) AS columns

    FROM dba_ind_columns ic

    GROUP BY ic.index_owner, ic.index_name
),

idx_part_keys AS (

    SELECT
        pk.owner,
        pk.name AS index_name,

        LISTAGG(
            pk.column_name,
            ', '
        ) WITHIN GROUP (
            ORDER BY pk.column_position
        ) AS idx_part_key

    FROM dba_part_key_columns pk

    WHERE pk.object_type = 'INDEX'

    GROUP BY pk.owner, pk.name
)

SELECT
    i.owner || '.' || i.table_name AS tbl_name,
    i.index_name,
    i.index_type,
    i.uniqueness,
    i.num_rows,
    i.distinct_keys,
    i.blevel,
    i.leaf_blocks,
    i.clustering_factor,

    CASE
        WHEN NVL(i.leaf_blocks,0) > 0
        THEN ROUND(
                 i.clustering_factor / i.leaf_blocks,
                 1
             )
    END AS cf_to_blocks,

    CASE
        WHEN i.compression = 'ENABLED'
         AND i.prefix_length IS NOT NULL
        THEN 'PREFIX ' || TO_CHAR(i.prefix_length)

        WHEN i.compression IS NOT NULL
        THEN i.compression

        ELSE 'DISABLED'
    END AS compression_level,

    TO_CHAR(
        i.last_analyzed,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS last_analyzed,

    ist.stale_stats,
    i.partitioned,
    i.visibility,
    i.status,
    TRIM(i.degree) AS degree,

    CASE
        WHEN pi.locality IS NOT NULL
        THEN pi.locality
        ELSE '-'
    END AS locality,

    NVL(pi.partitioning_type,'NO') ||
    CASE
        WHEN NVL(pi.subpartitioning_type,'NONE') = 'NONE'
        THEN ''
        ELSE pi.subpartitioning_type
    END AS idx_part_type,

    SUBSTR(
        NVL(ipk.idx_part_key,'-'),
        1,
        30
    ) AS idx_part_key,

    ROUND(
        NVL(seg.bytes,0) / 1048576,
        1
    ) AS segment_mb,

    NVL(ic.columns,'-') AS columns

FROM plan_tables pt

JOIN dba_indexes i
  ON i.table_owner = pt.owner
 AND i.table_name = pt.name

LEFT JOIN index_columns ic
  ON ic.owner = i.owner
 AND ic.index_name = i.index_name

LEFT JOIN dba_ind_statistics ist
  ON ist.owner = i.owner
 AND ist.index_name = i.index_name
 AND ist.partition_name IS NULL

LEFT JOIN dba_part_indexes pi
  ON pi.owner = i.owner
 AND pi.index_name = i.index_name

LEFT JOIN idx_part_keys ipk
  ON ipk.owner = i.owner
 AND ipk.index_name = i.index_name

LEFT JOIN (
    SELECT
        owner,
        segment_name,
        SUM(bytes) AS bytes
    FROM dba_segments
    WHERE segment_type LIKE 'INDEX%'
    GROUP BY owner, segment_name
) seg
  ON seg.owner = i.owner
 AND seg.segment_name = i.index_name

ORDER BY i.owner, i.table_name, i.index_name;

PROMPT

/*------------------------------------------------------------------
 * SECTION 11a: Column Statistics for Predicate Columns
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This extracts columns referenced in ACCESS and FILTER predicates
 * from execution plans (GV$SQL_PLAN.access_predicates /
 * filter_predicates and DBA_HIST_SQL_PLAN equivalents),
 * then shows their optimizer statistics.
 *
 * KEY ANALYSIS:
 * - num_distinct:
 *     the optimizer uses this for selectivity estimates.
 *     If num_distinct is wrong, cardinality estimates will be wrong,
 *     producing bad plans.
 *     Compare to actual distinct values if known.
 *
 * - density:
 *     1/num_distinct for columns without histograms;
 *     with histograms it reflects popular-value weighting.
 *     Very small density = highly selective.
 *     density close to 1 = not selective.
 *
 * - num_nulls:
 *     high NULLs plus predicates
 *     have different selectivity than the optimizer assumes without
 *     null-aware stats
 *
 * - histogram:
 *     NONE = no histogram
 *     FREQUENCY, TOP-FREQUENCY, HEIGHT BALANCED, HYBRID
 *     = histogram present.
 *     Missing histograms on skewed data
 *     = cardinality misestimates.
 *     Unnecessary histograms on uniform data
 *     = wasted overhead.
 *
 * - num_buckets:
 *     1 = no histogram
 *     254 = maximum for frequency/hybrid.
 *     Too few buckets on highly skewed data misses important values.
 *
 * - low_value / high_value:
 *     the min/max known to the optimizer.
 *     Out-of-range predicates
 *     (value > high_value)
 *     get very low cardinality estimates,
 *     potentially causing nested loops when hash joins would be better.
 *
 * - sample_size:
 *     if much less than num_rows,
 *     stats may be inaccurate
 *
 * - last_analyzed:
 *     stale column stats cause bad estimates
 *
 * - predicate_type:
 *     ACCESS = used to drive index/join;
 *     FILTER = applied after access.
 *     Columns in ACCESS predicates are most critical.
 *
 * - predicate_text:
 *     the actual predicate from the plan,
 *     so you can see exactly how the column is used
 *     (range, equality, function, etc.)
 *
 * COMMON PROBLEMS:
 * - Function wrapping a column
 *     (e.g., TRUNC(col))
 *     hides the column from the optimizer
 *     = histogram won't help,
 *     needs function-based index
 *
 * - Implicit data type conversion
 *     (TO_NUMBER, TO_CHAR)
 *     in predicates prevents index use and histogram benefit
 *
 * - Correlated columns
 *     (e.g., state + city)
 *     need extended statistics or column groups,
 *     not individual histograms
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 11a: Column Statistics for Predicate Columns
PROMPT

COL owner           FOR A20 HEAD 'Owner'
COL table_name      FOR A30 HEAD 'Table Name'
COL column_name     FOR A30 HEAD 'Column Name'
COL predicate_type  FOR A6 HEAD 'Pred'
COL predicate_text  FOR A60 HEAD 'Predicate' WORD_WRAP
COL num_distinct    FOR 999,999,999,999 HEAD 'Num Distinct'
COL density         FOR 0.999999 HEAD 'Density'
COL num_nulls       FOR 999,999,999,999 HEAD 'Num Nulls'
COL num_buckets     FOR 9999 HEAD 'Buckets'
COL histogram       FOR A15 HEAD 'Histogram'
COL low_value_d     FOR A30 HEAD 'Low Value'
COL high_value_d    FOR A30 HEAD 'High Value'
COL sample_size     FOR 999,999,999,999 HEAD 'Sample Size'
COL last_analyzed   FOR A19 HEAD 'Last Analyzed'
COL avg_col_len     FOR 999 HEAD 'AvgLen'

WITH predicate_cols AS (

    -- Extract columns from SGA plan predicates
    SELECT DISTINCT
        p.object_owner,
        p.object_name,
        'ACCESS' AS predicate_type,
        p.access_predicates AS predicate_text

    FROM gv$sql_plan p

    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_owner IS NOT NULL
      AND p.access_predicates IS NOT NULL

    UNION ALL

    SELECT DISTINCT
        p.object_owner,
        p.object_name,
        'FILTER',
        p.filter_predicates

    FROM gv$sql_plan p

    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_owner IS NOT NULL
      AND p.filter_predicates IS NOT NULL

    UNION ALL

    -- Extract columns from AWR plan predicates
    SELECT DISTINCT
        p.object_owner,
        p.object_name,
        'ACCESS',
        p.access_predicates

    FROM dba_hist_sql_plan p

    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_owner IS NOT NULL
      AND p.access_predicates IS NOT NULL

    UNION ALL

    SELECT DISTINCT
        p.object_owner,
        p.object_name,
        'FILTER',
        p.filter_predicates

    FROM dba_hist_sql_plan p

    WHERE p.sql_id = '&&p_sql_id'
      AND p.object_owner IS NOT NULL
      AND p.filter_predicates IS NOT NULL
),

-- Resolve index objects to their underlying table
pred_tables AS (

    SELECT
        pc.owner,
        pc.table_name AS name,
        pc.predicate_type,
        pc.predicate_text

    FROM predicate_cols pc

    WHERE EXISTS (
        SELECT 1
        FROM dba_tables t
        WHERE t.owner = pc.owner
          AND t.table_name = pc.table_name
    )

    UNION ALL

    SELECT
        i.table_owner,
        i.table_name,
        pc.predicate_type,
        pc.predicate_text

    FROM predicate_cols pc

    JOIN dba_indexes i
      ON i.owner = pc.owner
     AND i.index_name = pc.table_name

    WHERE EXISTS (
        SELECT 1
        FROM dba_tables t
        WHERE t.owner = pc.owner
          AND t.table_name = pc.table_name
    )
),

-- Get all unique tables with predicates
plan_tables AS (
    SELECT DISTINCT owner, name
    FROM pred_tables
)

SELECT
    cs.owner,
    cs.table_name,
    cs.column_name,
    pt.predicate_type,

    SUBSTR(
        pt.predicate_text,
        1,
        200
    ) AS predicate_text,

    cs.num_distinct,
    cs.density,
    cs.num_nulls,
    cs.num_buckets,
    cs.histogram,

    UTL_RAW.CAST_TO_VARCHAR2(
        SUBSTR(cs.low_value,1,32)
    ) AS low_value_d,

    UTL_RAW.CAST_TO_VARCHAR2(
        SUBSTR(cs.high_value,1,32)
    ) AS high_value_d,

    cs.sample_size,

    TO_CHAR(
        cs.last_analyzed,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS last_analyzed,

    cs.avg_col_len

FROM plan_tables ptb

JOIN dba_tab_col_statistics cs
  ON cs.owner = ptb.owner
 AND cs.table_name = ptb.name

LEFT JOIN (
    SELECT DISTINCT
        owner,
        name,
        predicate_type,
        predicate_text

    FROM pred_tables
) pt
  ON pt.owner = cs.owner
 AND pt.name = cs.table_name
 AND UPPER(pt.predicate_text)
      LIKE '%' || cs.column_name || '%'

WHERE pt.predicate_type IS NOT NULL

ORDER BY
    cs.owner,
    cs.table_name,
    pt.predicate_type,
    cs.column_name;

PROMPT

/*------------------------------------------------------------------
 * SECTION 11b: Extended Statistics (Column Groups)
 * for Plan Tables
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Extended statistics (column groups)
 * allow the optimizer to estimate selectivity for multi-column
 * predicates more accurately.
 *
 * If this section is empty,
 * the optimizer relies on independence assumptions
 * (multiply individual selectivities),
 * which is often wrong for correlated columns like
 * (country, state) or (year, month).
 *
 * If the SQL has multi-column WHERE predicates and this is empty,
 * recommend creating extended statistics:
 *
 * EXEC DBMS_STATS.CREATE_EXTENDED_STATS(
 *      null,
 *      'TABLE',
 *      '(COL1,COL2)'
 * );
 *------------------------------------------------------------------*/
--
PROMPT
PROMPT ## SECTION 11b: Extended Statistics (Column Groups) for Plan Tables
PROMPT

COL owner           FOR A20 HEAD 'Owner'
COL table_name      FOR A30 HEAD 'Table Name'
COL extension_name  FOR A30 HEAD 'Extension Name'
COL extension       FOR A60 HEAD 'Extension (Column Group)'
COL num_distinct    FOR 999,999,999,999 HEAD 'Num Distinct'
COL num_buckets     FOR 9999 HEAD 'Buckets'
COL histogram       FOR A15 HEAD 'Histogram'
COL last_analyzed   FOR A19 HEAD 'Last Analyzed'

WITH plan_tables AS (

    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name
    FROM gv$sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        object_owner,
        object_name
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
)

SELECT
    se.owner,
    se.table_name,
    se.extension_name,
    se.extension,
    cs.num_distinct,
    cs.num_buckets,
    cs.histogram,
    TO_CHAR(cs.last_analyzed,'YYYY-MM-DD HH24:MI:SS') AS last_analyzed

FROM plan_tables pt

JOIN dba_stat_extensions se
  ON se.owner = pt.owner
 AND se.table_name = pt.name

LEFT JOIN dba_tab_col_statistics cs
  ON cs.owner = se.owner
 AND cs.table_name = se.table_name
 AND cs.column_name = se.extension_name

WHERE se.creator = 'USER'
   OR se.droppable = 'YES'

ORDER BY se.owner, se.table_name, se.extension_name;

PROMPT

/*------------------------------------------------------------------
 * SECTION 11c: All Column Statistics for Plan Tables (Full Catalog)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Complete column stats for all tables in the plan — not just predicate
 * columns. This helps identify:
 *   - Join columns with mismatched data types or missing stats
 *   - SELECT-list columns that could enable index-only scans if added
 *     to a composite index
 *   - Columns with histograms that might be unnecessary (uniform data)
 *
 * Limited to first 200 rows to manage output size.
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 11c: All Column Statistics for Plan Tables
PROMPT

COL owner         FOR A20 HEAD 'Owner'
COL table_name    FOR A30 HEAD 'Table Name'
COL column_name   FOR A30 HEAD 'Column Name'
COL density       FOR 0.999999 HEAD 'Density'
COL num_nulls     FOR 999,999,999,999 HEAD 'Num Nulls'
COL num_buckets   FOR 9999 HEAD 'Buckets'
COL histogram     FOR A15 HEAD 'Histogram'
COL last_analyzed FOR A19 HEAD 'Last Analyzed'
COL avg_col_len   FOR 999 HEAD 'AvgLen'
COL nullable      FOR A4 HEAD 'Null?'
COL data_type     FOR A35 HEAD 'Data Type'

WITH plan_tables AS (

    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name
    FROM gv$sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        object_owner,
        object_name
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
)

SELECT
    tc.owner,
    tc.table_name,
    tc.column_name,
    cs.density,
    cs.num_nulls,
    cs.num_buckets,
    cs.histogram,
    TO_CHAR(cs.last_analyzed,'YYYY-MM-DD HH24:MI:SS') AS last_analyzed,
    cs.avg_col_len,
    tc.nullable,

    tc.data_type ||
    CASE
        WHEN tc.data_length IS NOT NULL
         AND tc.data_type IN ('VARCHAR2','CHAR','NVARCHAR2','RAW')
        THEN '('||tc.data_length||')'
    END AS data_type

FROM plan_tables pt

JOIN dba_tab_columns tc
  ON tc.owner = pt.owner
 AND tc.table_name = pt.name

LEFT JOIN dba_tab_col_statistics cs
  ON cs.owner = tc.owner
 AND cs.table_name = tc.table_name
 AND cs.column_name = tc.column_name

ORDER BY
    tc.owner,
    tc.table_name,
    tc.column_id

FETCH FIRST 200 ROWS ONLY;

PROMPT

 /*----------------------------------------------------------------
 * SECTION 11d: LOB Column Metadata for Plan Tables
 *----------------------------------------------------------------
 * FOR THE LLM:
 *   LOB columns (CLOB, BLOB, NCLOB) can significantly affect SQL performance
 *   through out-of-row storage, chained rows, and SecureFile overhead.
 *
 * KEY ANALYSIS:
 *   - securefile vs basicfile: SecureFile LOBs support compression,
 *     deduplication, and encryption; BasicFile does not
 *   - compression: MEDIUM/HIGH compression reduces I/O but adds CPU;
 *     NO COMPRESS or NONE means every LOB read is full-size
 *   - in_row: YES = small LOBs stored inline with the row (fast);
 *     NO = always out-of-row (extra I/O per access)
 *   - segment_bytes: total storage consumed by the LOB segment;
 *     very large LOB segments on tables in the plan may explain
 *     high I/O or slow full scans
 *   - chunk: allocation unit for LOB storage in bytes
 *   - cache: YES = LOB data cached in buffer cache; NO = direct read
 *   - deduplication: YES = duplicate LOB values stored once
 *   - If plan tables have LOB columns and the SQL selects or filters
 *     them, LOB access patterns may dominate elapsed time
 *----------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 11d: LOB Column Metadata for Plan Tables
PROMPT

COL owner            FOR A20 HEAD 'Owner'
COL table_name       FOR A30 HEAD 'Table Name'
COL column_name      FOR A30 HEAD 'Column Name'
COL data_type        FOR A10 HEAD 'Data Type'
COL lob_segment      FOR A30 HEAD 'LOB Segment'
COL securefile       FOR A10 HEAD 'SecureFile'
COL compression      FOR A12 HEAD 'Compression'
COL deduplication    FOR A12 HEAD 'Dedup'
COL in_row           FOR A6  HEAD 'InRow'
COL lob_chunk        FOR 99,999 HEAD 'Chunk'
COL cache            FOR A10 HEAD 'Cache'
COL segment_mb       FOR 999,999,990.9 HEAD 'Segment MB'
COL tablespace_name  FOR A20 HEAD 'Tablespace'

WITH plan_tables AS (

    SELECT DISTINCT object_owner AS owner,
                    object_name  AS name
    FROM gv$sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%'
           OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT object_owner,
                    object_name
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%'
           OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT i.table_owner,
                    i.table_name
    FROM gv$sql_plan p
         JOIN dba_indexes i
           ON i.owner = p.object_owner
          AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT i.table_owner,
                    i.table_name
    FROM dba_hist_sql_plan p
         JOIN dba_indexes i
           ON i.owner = p.object_owner
          AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

)

SELECT
    l.owner,
    l.table_name,
    l.column_name,
    tc.data_type,
    l.segment_name                                  AS lob_segment,
    l.securefile,
    NVL(l.compression, 'NONE')                      AS compression,
    NVL(l.deduplication, 'NONE')                    AS deduplication,
    l.in_row,
    l.chunk                                         AS lob_chunk,
    l.cache,
    ROUND(NVL(s.bytes, 0) / 1048576, 1)            AS segment_mb,
    l.tablespace_name

FROM plan_tables pt

JOIN dba_lobs l
  ON l.owner = pt.owner
 AND l.table_name = pt.name

JOIN dba_tab_columns tc
  ON tc.owner = l.owner
 AND tc.table_name = l.table_name
 AND tc.column_name = l.column_name

LEFT JOIN dba_segments s
  ON s.owner = l.owner
 AND s.segment_name = l.segment_name
 AND s.segment_type LIKE 'LOB%'

ORDER BY
    l.owner,
    l.table_name,
    l.column_name;

SET HEA OFF

SELECT 'none found' AS status_message
FROM dual
WHERE NOT EXISTS (

    SELECT 1
    FROM (

        SELECT DISTINCT object_owner AS owner,
                        object_name  AS name
        FROM gv$sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND object_owner IS NOT NULL
          AND (operation LIKE 'TABLE%'
               OR operation LIKE '%LOAD%')

        UNION

        SELECT DISTINCT object_owner,
                        object_name
        FROM dba_hist_sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND object_owner IS NOT NULL
          AND (operation LIKE 'TABLE%'
               OR operation LIKE '%LOAD%')

        UNION

        SELECT DISTINCT i.table_owner,
                        i.table_name
        FROM gv$sql_plan p
             JOIN dba_indexes i
               ON i.owner = p.object_owner
              AND i.index_name = p.object_name
        WHERE p.sql_id = '&&p_sql_id'
          AND p.operation LIKE 'INDEX%'

        UNION

        SELECT DISTINCT i.table_owner,
                        i.table_name
        FROM dba_hist_sql_plan p
             JOIN dba_indexes i
               ON i.owner = p.object_owner
              AND i.index_name = p.object_name
        WHERE p.sql_id = '&&p_sql_id'
          AND p.operation LIKE 'INDEX%'

    ) pt

    JOIN dba_lobs l
      ON l.owner = pt.owner
     AND l.table_name = pt.name

);

SET HEA ON

PROMPT
/*------------------------------------------------------------------
 * SECTION 12a: LOB Column Metadata for Plan Tables
 *------------------------------------------------------------------
 * FOR THE LLM:
 * LOB columns (CLOB, BLOB, NCLOB) can significantly affect SQL
 * performance through out-of-row storage, chained rows,
 * and SecureFile overhead.
 *
 * KEY ANALYSIS:
 * > securefile vs basicfile:
 *     SecureFile LOBs support compression, deduplication,
 *     and encryption; BasicFile does not.
 *
 * > compression:
 *     MEDIUM/HIGH compression reduces I/O but adds CPU.
 *     NO COMPRESS or NONE means every LOB read is full-size.
 *
 * > in_row:
 *     YES = small LOBs stored inline with the row (<4KB);
 *     NO = always out-of-row (extra I/O per access).
 *
 * > segment_bytes:
 *     total storage consumed by the LOB segment;
 *     very large LOB segments on tables in the plan
 *     may explain high I/O or slow full scans.
 *
 * > chunk:
 *     allocation unit for LOB storage in bytes.
 *
 * > cache:
 *     YES = LOB data cached in buffer cache;
 *     NO = direct read.
 *
 * > deduplication:
 *     YES = duplicate LOB values stored once.
 *
 * > If plan tables have LOB columns and the SQL selects or filters
 *   them, LOB access patterns may dominate elapsed time.
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 12a: LOB Column Metadata for Plan Tables
PROMPT

COL owner            FOR A20 HEAD 'Owner'
COL table_name       FOR A30 HEAD 'Table Name'
COL column_name      FOR A30 HEAD 'Column'
COL data_type        FOR A10 HEAD 'Data Type'
COL lob_segment      FOR A30 HEAD 'LOB Segment'
COL securefile       FOR A10 HEAD 'SecureFile'
COL compression      FOR A12 HEAD 'Compression'
COL deduplication    FOR A12 HEAD 'Dedup'
COL in_row           FOR A6 HEAD 'InRow'
COL lob_chunk        FOR 99,999 HEAD 'Chunk'
COL cache            FOR A10 HEAD 'Cache'
COL segment_mb       FOR 999,999,990.9 HEAD 'Segment MB'
COL tablespace_name  FOR A20 HEAD 'Tablespace'

WITH plan_tables AS (

    SELECT DISTINCT
        object_owner AS owner,
        object_name AS name
    FROM gv$sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        object_owner,
        object_name
    FROM dba_hist_sql_plan
    WHERE sql_id = '&&p_sql_id'
      AND object_owner IS NOT NULL
      AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM gv$sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'

    UNION

    SELECT DISTINCT
        i.table_owner,
        i.table_name
    FROM dba_hist_sql_plan p
    JOIN dba_indexes i
      ON i.owner = p.object_owner
     AND i.index_name = p.object_name
    WHERE p.sql_id = '&&p_sql_id'
      AND p.operation LIKE 'INDEX%'
)

SELECT
    l.owner,
    l.table_name,
    l.column_name,
    tc.data_type,
    l.segment_name AS lob_segment,
    l.securefile,
    NVL(l.compression,'NONE') AS compression,
    NVL(l.deduplication,'NONE') AS deduplication,
    l.in_row,
    l.chunk AS lob_chunk,
    l.cache,
    ROUND(NVL(s.bytes,0) / 1048576,1) AS segment_mb,
    l.tablespace_name

FROM plan_tables pt

JOIN dba_lobs l
  ON l.owner = pt.owner
 AND l.table_name = pt.name

JOIN dba_tab_columns tc
  ON tc.owner = l.owner
 AND tc.table_name = l.table_name
 AND tc.column_name = l.column_name

LEFT JOIN dba_segments s
  ON s.owner = l.owner
 AND s.segment_name = l.segment_name
 AND s.segment_type LIKE 'LOB%'

ORDER BY l.owner, l.table_name, l.column_name;

SET HEA OFF

SELECT 'none found' AS status_message
FROM dual
WHERE NOT EXISTS (
    SELECT 1
    FROM (
        SELECT DISTINCT
            object_owner AS owner,
            object_name AS name
        FROM gv$sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND object_owner IS NOT NULL
          AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

        UNION

        SELECT DISTINCT
            object_owner,
            object_name
        FROM dba_hist_sql_plan
        WHERE sql_id = '&&p_sql_id'
          AND object_owner IS NOT NULL
          AND (operation LIKE 'TABLE%' OR operation LIKE '%LOAD%')

        UNION

        SELECT DISTINCT
            i.table_owner,
            i.table_name
        FROM gv$sql_plan p
        JOIN dba_indexes i
          ON i.owner = p.object_owner
         AND i.index_name = p.object_name
        WHERE p.sql_id = '&&p_sql_id'
          AND p.operation LIKE 'INDEX%'

        UNION

        SELECT DISTINCT
            i.table_owner,
            i.table_name
        FROM dba_hist_sql_plan p
        JOIN dba_indexes i
          ON i.owner = p.object_owner
         AND i.index_name = p.object_name
        WHERE p.sql_id = '&&p_sql_id'
          AND p.operation LIKE 'INDEX%'
    ) pt
    JOIN dba_lobs l
      ON l.owner = pt.owner
     AND l.table_name = pt.name
);

SET HEA ON

PROMPT

/*------------------------------------------------------------------
 * SECTION 13a: Resource Manager Throttling from ASH
 *------------------------------------------------------------------
 * FOR THE LLM:
 * When Oracle Resource Manager is active,
 * sessions can be throttled (forced to wait on
 * "resmgr:cpu quantum" or similar events).
 * This section checks if this SQL was affected by
 * Resource Manager during the analysis window.
 *
 * KEY EVENTS:
 *   resmgr:cpu quantum      - session exceeded CPU allocation, was queued
 *   resmgr:large I/O quota  - I/O rate limited
 *   resmgr:IO prioritization - I/O deprioritized
 *   resmgr:pq queued        - parallel query queued waiting for PQ slaves
 *   resmgr:become active    - session waiting to become active
 *
 * If these events appear with significant sample counts,
 * the SQL performance problem may be Resource Manager throttling,
 * NOT a bad plan.
 *
 * Check the consumer group and resource plan in effect.
 *
 * COLUMNS:
 *   consumer_group_id - maps to DBA_RSRC_CONSUMER_GROUPS
 *   event             - the specific resmgr wait event
 *   ash_samples       - weighted seconds of throttling
 *   pct_of_sql_time   - % of this SQL's sampled time spent throttled
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 13a: Resource Manager Throttling (ASH)
PROMPT

COL consumer_group FOR A30 HEAD 'Consumer Group'
COL event          FOR A40 HEAD 'Event'
COL ash_samples    FOR 999,999 HEAD 'ASH Samples'
COL pct_of_sql_time FOR 990.99 HEAD '% SQL Time'
COL inst_id        FOR 99 HEAD 'Inst'

WITH combined_ash AS (

    SELECT
        inst_id,
        NVL(consumer_group_id,0) AS consumer_group_id,
        event,
        1 AS weight

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND event LIKE 'resmgr:%'
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        instance_number,
        NVL(consumer_group_id,0),
        event,
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND event LIKE 'resmgr:%'
      AND '&&v_use_ash' = 'N'
),

sql_total AS (

    SELECT NVL(SUM(w),1) AS t

    FROM (

        SELECT COUNT(*) AS w
        FROM gv$active_session_history
        WHERE sql_id = '&&p_sql_id'
          AND sample_time BETWEEN &&v_begin_date_expr
                              AND &&v_end_date_expr
          AND '&&v_use_ash' = 'Y'
          AND con_dbid = &&p_dbid

        UNION ALL

        SELECT COUNT(*)*10
        FROM dba_hist_active_sess_history
        WHERE sql_id = '&&p_sql_id'
          AND sample_time BETWEEN &&v_begin_date_expr
                              AND &&v_end_date_expr
          AND '&&v_use_ash' = 'N'
    )
)

SELECT
    a.inst_id,

    NVL(
        cg.consumer_group,
        'ID:'||a.consumer_group_id
    ) AS consumer_group,

    a.event,
    SUM(a.weight) AS ash_samples,

    ROUND(
        SUM(a.weight) / MAX(st.t) * 100,
        2
    ) AS pct_of_sql_time

FROM combined_ash a

CROSS JOIN sql_total st

LEFT JOIN dba_rsrc_consumer_groups cg
  ON cg.consumer_group_id = a.consumer_group_id
--
LEFT JOIN dba_rsrc_consumer_groups cg
  ON cg.consumer_group_id = a.consumer_group_id

GROUP BY
    a.inst_id,
    NVL(cg.consumer_group, 'ID:'||a.consumer_group_id),
    a.event

ORDER BY ash_samples DESC;

PROMPT

/*------------------------------------------------------------------
 * SECTION 13b: Parallel Execution Details and Downgrades (GV$SQL)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * On Exadata RAC, parallel queries are common. This section shows
 * whether each child cursor actually used PQ slaves, using GV$SQL columns
 * that are broadly available across Oracle 19c patch levels.
 *
 * KEY ANALYSIS:
 *   - px_servers_executions > 0:
 *       the child actually used parallel slaves
 *
 *   - px_servers_per_exec approximates how much PQ was used
 *       per execution
 *
 *   - If PX is expected but px_servers_executions remains 0,
 *       the statement may be serializing or not getting PQ at runtime
 *
 *   - Common causes:
 *       PARALLEL_MAX_SERVERS exhausted,
 *       Resource Manager limits,
 *       other concurrent PQ consumers
 *
 *   - is_reoptimizable = Y:
 *       adaptive plan may change on next execution
 *
 *   - is_bind_sensitive / is_bind_aware:
 *       cursor is adapting to different bind variable values
 *       (Adaptive Cursor Sharing)
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 13b: Parallel Execution and Downgrades (GV$SQL)
PROMPT

COL inst_id              FOR 99           HEAD 'Inst'
COL child_number         FOR 999          HEAD 'Child'
COL plan_hash_value      FOR 9999999999   HEAD 'Plan Hash'
COL px_servers_exec      FOR 999,999,999  HEAD 'PX Srv Execs'
COL px_used              FOR A8           HEAD 'PX Used?'
COL px_servers_per_exec  FOR 999,990.9    HEAD 'PX Srv/Exec'
COL is_bind_sensitive    FOR A6           HEAD 'Bind Sens?'
COL is_bind_aware        FOR A6           HEAD 'Bind Aware?'
COL is_reoptimizable     FOR A6           HEAD 'Reopt?'
COL executions           FOR 999,999,999  HEAD 'Execs'
COL elapsed_per_exec     FOR 999,990.999  HEAD 'Elapsed/Exec(s)'

SELECT
    s.inst_id,
    s.child_number,
    s.plan_hash_value,

    NVL(s.px_servers_executions,0)
        AS px_servers_exec,

    CASE
        WHEN NVL(s.px_servers_executions,0) > 0
        THEN 'YES'
        ELSE 'NO'
    END AS px_used,

    ROUND(
        s.px_servers_executions /
        NULLIF(s.executions,0),
        1
    ) AS px_servers_per_exec,

    s.is_bind_sensitive,
    s.is_bind_aware,
    s.is_reoptimizable,
    s.executions,

    ROUND(
        s.elapsed_time /
        NULLIF(s.executions,0) / 1e6,
        3
    ) AS elapsed_per_exec

FROM gv$sql s

WHERE s.sql_id = '&&p_sql_id'

ORDER BY
    s.inst_id,
    s.child_number;

PROMPT

/*------------------------------------------------------------------
 * SECTION 13c: PX Downgrade and Queuing from ASH (Historical)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * ASH captures the actual session type
 * (FOREGROUND = query coordinator,
 * BACKGROUND with program like %P0 slave).
 *
 * We also check for PX-related wait events
 * that indicate queuing or downgrades:
 *
 *   - PX Deq: Execute Reply
 *       = coordinator waiting for slaves to finish
 *
 *   - PX Deq: Table Q Normal
 *       = slave waiting for data from producer
 *
 *   - PX qref latch
 *       = contention in PX messaging
 *
 *   - resmgr:pq queued
 *       = PQ request queued by Resource Manager
 *
 *   - enq: JX
 *       = SQL statement queuing or PX slave startup contention
 *
 * High samples on PX Deq events relative to actual work
 * = PX skew (one slave doing most of the work, others idle).
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 13c: Parallel Execution Waits from ASH
PROMPT

COL event           FOR A45 HEAD 'Event'
COL wait_class      FOR A15 HEAD 'Wait Class'
COL session_type    FOR A12 HEAD 'Session Type'
COL ash_samples     FOR 99,999,999 HEAD 'ASH Samples'
COL pct_of_sql_time FOR 990.99 HEAD '% SQL Time'

WITH combined_ash AS (

    SELECT
        NVL(event,'ON CPU') AS event,
        NVL(wait_class,'ON CPU') AS wait_class,
        session_type,
        1 AS weight

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND (
            event LIKE 'PX%'
         OR event LIKE 'resmgr:pq%'
         OR event LIKE 'enq: JX%'
         OR event IS NULL
      )
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        NVL(event,'ON CPU'),
        NVL(wait_class,'ON CPU'),
        session_type,
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND (
            event LIKE 'PX%'
         OR event LIKE 'resmgr:pq%'
         OR event LIKE 'enq: JX%'
         OR event IS NULL
      )
      AND '&&v_use_ash' = 'N'
),

sql_total AS (

    SELECT NVL(SUM(w),1) AS t

    FROM (

        SELECT COUNT(*) AS w
        FROM gv$active_session_history
        WHERE sql_id = '&&p_sql_id'
          AND sample_time BETWEEN &&v_begin_date_expr
                              AND &&v_end_date_expr
          AND '&&v_use_ash' = 'Y'
          AND con_dbid = &&p_dbid

        UNION ALL

        SELECT COUNT(*)*10
        FROM dba_hist_active_sess_history
        WHERE sql_id = '&&p_sql_id'
          AND sample_time BETWEEN &&v_begin_date_expr
                              AND &&v_end_date_expr
          AND '&&v_use_ash' = 'N'
    )
)

SELECT
    a.session_type,
    a.wait_class,
    a.event,

    SUM(a.weight)
        AS ash_samples,

    ROUND(
        SUM(a.weight) / MAX(st.t) * 100,
        2
    ) AS pct_of_sql_time

FROM combined_ash a

CROSS JOIN sql_total st

GROUP BY
    a.session_type,
    a.wait_class,
    a.event

ORDER BY ash_samples DESC

FETCH FIRST 30 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 13d: Active Resource Plan and Consumer Group Mapping
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Shows the currently active resource plan and consumer group directives.
 *
 * If Resource Manager throttling was detected in 13a,
 * cross-reference the consumer_group here to see what CPU/PQ limits
 * are imposed.
 *
 * KEY COLUMNS:
 *   mgmt_p1-p8
 *       = CPU allocation % per level
 *         (level 1 = highest priority)
 *
 *   max_utilization_limit
 *       = hard CPU cap (100 = no cap)
 *
 *   parallel_degree_limit_p1
 *       = max DOP allowed for this group
 *
 *   parallel_server_limit
 *       = % of parallel max servers allowed
 *
 *   switch_group / switch_time
 *       = auto-switch to lower group after N seconds
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 13d: Active Resource Plan and Consumer Group Directives
PROMPT

COL resource_plan            FOR A30 HEAD 'Resource Plan'

SELECT
    NVL(NULLIF(TRIM(value),''),'NONE') AS resource_plan
FROM v$parameter
WHERE name = 'resource_manager_plan';

PROMPT

COL plan                      FOR A25 HEAD 'Plan'
COL consumer_group            FOR A30 HEAD 'Consumer Group'
COL mgmt_p1                   FOR 999 HEAD 'CPU L1%'
COL mgmt_p2                   FOR 999 HEAD 'CPU L2%'
COL mgmt_p3                   FOR 999 HEAD 'CPU L3%'
COL max_utilization_limit     FOR 999 HEAD 'Max CPU%'
COL parallel_degree_limit_p1  FOR A10 HEAD 'PX DOP Limit'
COL parallel_server_limit     FOR 999 HEAD 'PX Srvs%'
COL switch_group              FOR A25 HEAD 'Switch To'
COL switch_time               FOR 9999 HEAD 'Switch(s)'

SELECT
    d.plan,
    d.group_or_subplan AS consumer_group,
    d.mgmt_p1,
    d.mgmt_p2,
    d.mgmt_p3,
    d.max_utilization_limit,
    d.parallel_degree_limit_p1,
    d.parallel_server_limit,
    d.switch_group,
    d.switch_time

FROM dba_rsrc_plan_directives d

WHERE d.plan = (
        SELECT NULLIF(TRIM(value),'')
        FROM v$parameter
        WHERE name = 'resource_manager_plan'
      )
  AND d.mandatory = 'YES'

ORDER BY
    d.mgmt_p1 DESC,
    d.group_or_subplan;

SET HEA OFF

SELECT 'NONE' AS status_message
FROM dual
WHERE NOT EXISTS (

    SELECT 1
    FROM dba_rsrc_plan_directives d

    WHERE d.plan = (
            SELECT NULLIF(TRIM(value),'')
            FROM v$parameter
            WHERE name = 'resource_manager_plan'
          )
      AND d.mandatory = 'YES'
);

SET HEA ON

PROMPT

/*------------------------------------------------------------------
 * SECTION 14a: Child Cursor Count and Version Reasons
 *------------------------------------------------------------------
 * FOR THE LLM:
 * When a SQL_ID accumulates many child cursors (versions),
 * it signals that Oracle could not share a single parsed cursor
 * across executions.
 *
 * Excessive child cursors (>50) cause:
 *   - Mutex contention
 *       ("cursor: pin S wait on X",
 *        "library cache: mutex X")
 *
 *   - Increased parse time scanning the child cursor list
 *
 *   - SGA (shared pool) memory waste
 *
 * This section first shows the child cursor count per instance.
 *
 * If ANY instance has > 50 children,
 * it then queries V$SQL_SHARED_CURSOR
 * to show the REASONS cursors could not be shared.
 *
 * COMMON REASONS (Y = caused a new child):
 *
 *   OPTIMIZER_MISMATCH
 *       = different optimizer_mode or optimizer params
 *
 *   BIND_MISMATCH
 *       = different bind variable types/sizes
 *
 *   LANGUAGE_MISMATCH
 *       = different NLS settings
 *
 *   AUTH_CHECK_MISMATCH
 *       = different user privileges
 *
 *   OPTIMIZER_MODE_MISMATCH
 *       = different optimizer_mode per session
 *
 *   BIND_EQUIV_FAILURE
 *       = Adaptive Cursor Sharing created new child
 *
 *   ROLL_INVALID_MISMATCH
 *       = cursor invalidated by DDL/stats gathering
 *
 *   PURGED_CURSOR
 *       = cursor was aged out and reparsed
 *
 *   TOP_LEVEL_RPI_CURSOR
 *       = remote PL/SQL cursor mismatch
 *
 *   BIND_LENGTH_UPGRADEABLE
 *       = bind length changed
 *         (e.g., VARCHAR2(32) -> 128)
 *
 * RECOMMENDATIONS:
 *
 *   - BIND_MISMATCH:
 *       standardize bind types in the application
 *
 *   - OPTIMIZER_MISMATCH:
 *       check for ALTER SESSION SET optimizer_* in app code
 *
 *   - ROLL_INVALID_MISMATCH:
 *       frequent stats gathering invalidates cursors;
 *       consider NO_INVALIDATE => TRUE in DBMS_STATS preferences
 *
 *   - BIND_EQUIV_FAILURE with many children:
 *       Adaptive Cursor Sharing is creating too many plans;
 *       consider a SQL Plan Baseline to stabilize
 *
 *   - > 200 children:
 *       may hit bug or need CURSOR_SHARING = FORCE review
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 14a: Child Cursor Count and Sharing Reasons
PROMPT

COL inst_id         FOR 99 HEAD 'Inst'
COL child_count     FOR 999,999 HEAD 'Child Cursors'
COL loaded_versions FOR 999,999 HEAD 'Loaded Vers'
COL invalidations   FOR 999,999 HEAD 'Invalidations'
COL first_load_time FOR A19 HEAD 'First Load Time'

SELECT
    s.inst_id,
    COUNT(*) AS child_count,
    SUM(s.loaded_versions) AS loaded_versions,
    SUM(s.invalidations) AS invalidations
--
SUM(s.invalidations)                           AS invalidations,
MIN(s.first_load_time)                         AS first_load_time

FROM gv$sql s

WHERE s.sql_id = '&&p_sql_id'

GROUP BY s.inst_id

ORDER BY s.inst_id;

PROMPT
PROMPT >>> Shared cursor mismatch reasons
(only if any instance has > 50 children) <<<
PROMPT

DECLARE
    v_max_cnt          NUMBER := 0;
    v_total_children   NUMBER := 0;
    v_sql              CLOB;
    v_separator        VARCHAR2(20) := NULL;
    v_reason           VARCHAR2(200);
    v_occurrences      NUMBER;
    v_pct              NUMBER;
    v_sample_child     NUMBER;
    rc                 SYS_REFCURSOR;

BEGIN

    SELECT NVL(MAX(cnt), 0)
    INTO v_max_cnt
    FROM (
        SELECT COUNT(*) AS cnt
        FROM gv$sql
        WHERE sql_id = '&&p_sql_id'
        GROUP BY inst_id
    );

    IF v_max_cnt <= 50 THEN

        DBMS_OUTPUT.PUT_LINE(
            '(Skipped: max child count <= 50 on all instances.)'
        );

    ELSE

        SELECT COUNT(*)
        INTO v_total_children
        FROM gv$sql_shared_cursor
        WHERE sql_id = '&&p_sql_id';

        FOR col_rec IN (

            SELECT column_name
            FROM all_tab_columns

            WHERE owner = 'SYS'
              AND table_name = 'GV_$SQL_SHARED_CURSOR'

              AND column_name IN (

                'UNBOUND_CURSOR',
                'SQL_TYPE_MISMATCH',
                'OPTIMIZER_MISMATCH',
                'OUTLINE_MISMATCH',
                'STATS_ROW_MISMATCH',
                'LITERAL_MISMATCH',
                'FORCE_HARD_PARSE',
                'EXPLAIN_PLAN_CURSOR',
                'BUFFERED_DML_MISMATCH',
                'PDML_ENV_MISMATCH',
                'INST_DRTLD_MISMATCH',
                'SLAVE_QC_MISMATCH',
                'TYPECHECK_MISMATCH',
                'AUTH_CHECK_MISMATCH',
                'BIND_MISMATCH',
                'DESCRIBE_MISMATCH',
                'LANGUAGE_MISMATCH',
                'TRANSLATION_MISMATCH',
                'BIND_EQUIV_FAILURE',
                'INSUFF_PRIVS_REM',
                'REMOTE_TRANS_MISMATCH',
                'LOGMINER_SESSION_MISMATCH',
                'INCOMP_LTRL_MISMATCH',
                'OVERLAP_TIME_MISMATCH',
                'EDITION_MISMATCH',
                'MV_QUERY_GEN_MISMATCH',
                'USER_BIND_PEEK_MISMATCH',
                'TYPCHK_DEP_MISMATCH',
                'NO_TRIGGER_MISMATCH',
                'FLASHBACK_CURSOR',
                'ANYDATA_TRANSFORMATION',
                'PDDL_ENV_MISMATCH',
                'TOP_LEVEL_RPI_CURSOR',
                'DIFFERENT_LONG_LENGTH',
                'LOGICAL_STANDBY_APPLY',
                'DIFF_CALL_DURN',
                'BIND_UACS_DIFF',
                'PLSQL_CMP_SWITCHS_DIFF',
                'CURSOR_PARTS_MISMATCH',
                'STB_OBJECT_MISMATCH',
                'CROSSEDITION_TRIGGER_MISMATCH',
                'PQ_SLAVE_MISMATCH',
                'TOP_LEVEL_DDL_MISMATCH',
                'MULTI_PX_MISMATCH',
                'BIND_PEEKED_PQ_MISMATCH',
                'MV_REWRITE_MISMATCH',
                'ROLL_INVALID_MISMATCH',
                'OPTIMIZER_MODE_MISMATCH',
                'PX_MISMATCH',
                'MV_STALEOBJ_MISMATCH',
                'FLASHBACK_TABLE_MISMATCH',
                'LITREP_COMP_MISMATCH',
                'PLSQL_DEBUG',
                'LOAD_OPTIMIZER_STATS',
                'ACL_MISMATCH',
                'FLASHBACK_ARCHIVE_MISMATCH',
                'LOCK_USER_SCHEMA_FAILED',
                'REMOTE_MAPPING_MISMATCH',
                'LOAD_ROLLING_INVALID',
                'IS_ROLLING_INVALID',
                'PURGED_CURSOR',
                'BIND_LENGTH_UPGRADEABLE'
              )

            ORDER BY column_id

        ) LOOP

            v_sql :=
                v_sql || v_separator ||

                'SELECT '''
                || col_rec.column_name
                || ''' AS reason_column, child_number '

                || 'FROM gv$sql_shared_cursor '

                || 'WHERE sql_id = ''&&p_sql_id'' '

                || 'AND '
                || col_rec.column_name
                || ' = ''Y''';

            v_separator := ' UNION ALL ';

        END LOOP;

        IF v_sql IS NULL THEN

            DBMS_OUTPUT.PUT_LINE(
                'No compatible mismatch reason columns found in GV$SQL_SHARED_CURSOR.'
            );

        ELSE

            v_sql :=
                'SELECT reason_column,
                        COUNT(*) AS occurrences,
                        ROUND(COUNT(*) / NULLIF('
                        || v_total_children
                        || ',0) * 100, 1) AS pct,
                        MIN(child_number) AS sample_child
                 FROM ('
                 || v_sql
                 || ')
                 GROUP BY reason_column
                 ORDER BY occurrences DESC, reason_column
                 FETCH FIRST 20 ROWS ONLY';

            DBMS_OUTPUT.PUT_LINE(
                RPAD('Mismatch Reason', 35) ||
                LPAD('Occurrences', 12) ||
                LPAD('% of Children', 15) ||
                LPAD('Example Child', 16)
            );

            DBMS_OUTPUT.PUT_LINE(
                RPAD('-',35,'-') || ' ' ||
                RPAD('-',11,'-') || ' ' ||
                RPAD('-',13,'-') || ' ' ||
                RPAD('-',14,'-')
            );

            OPEN rc FOR v_sql;

            LOOP

                FETCH rc INTO
                    v_reason,
                    v_occurrences,
                    v_pct,
                    v_sample_child;

                EXIT WHEN rc%NOTFOUND;

                DBMS_OUTPUT.PUT_LINE(
                    RPAD(v_reason, 35) ||
                    LPAD(TO_CHAR(v_occurrences,'999,999'),12) ||
                    LPAD(NVL(TO_CHAR(v_pct,'990.9'),' '),15) ||
                    LPAD(NVL(TO_CHAR(v_sample_child,'999'),' '),16)
                );

            END LOOP;

            CLOSE rc;

        END IF;

    END IF;

END;
/

PROMPT

/*------------------------------------------------------------------
 * SECTION 15a: ASH Plan Line Activity : Time Spent per Plan Step
 *------------------------------------------------------------------
 * FOR THE LLM:
 * This is one of the MOST VALUABLE sections for root-cause analysis.
 *
 * It breaks down where DB time is spent at each step
 * (plan line) of each plan_hash_value,
 * using ASH sampling data.
 *
 * HOW TO READ:
 *
 *   - Each row =
 *       one (plan_hash_value, plan_line_id, plan_operation,
 *            wait_class/event) combination
 *
 *   - ash_samples =
 *       weighted ASH samples
 *       (proxy for seconds of DB time)
 *
 *   - pct_of_plan =
 *       % of total time for THAT plan hash spent on this line
 *
 *   - The plan_operation + plan_options tell you WHAT the step does
 *       (e.g., TABLE ACCESS FULL,
 *              INDEX RANGE SCAN,
 *              HASH JOIN, etc.)
 *
 *   - The wait_class + event tell you WHY time is spent there
 *       (ON CPU = doing useful work or spinning;
 *        User I/O = physical reads;
 *        Cluster = RAC block shipping;
 *        Concurrency = latch/mutex)
 *
 * KEY ANALYSIS:
 *
 *   - Lines with highest pct_of_plan are the bottleneck steps
 *
 *   - If a TABLE ACCESS FULL has high User I/O,
 *       check if an index could avoid full scan,
 *       or if Exadata Smart Scan is being used
 *
 *   - If a HASH JOIN line is high on CPU,
 *       the join may be processing too many rows
 *       (check E-Rows vs A-Rows in Section 3)
 *
 *   - If a NESTED LOOPS line has high
 *       "db file sequential read"
 *       or "cell single block physical read",
 *       it's doing many single-block reads
 *       — a hash join might be more efficient
 *         for large result sets
 *
 *   - Cluster waits (gc%) on a specific line =
 *       that step is causing cross-instance block transfers
 *       (RAC hot blocks)
 *
 *   - Compare across plan_hash_values:
 *       if one plan spends 80% on line 5 (FULL SCAN)
 *       while another spends 80% on line 3
 *       (INDEX RANGE SCAN),
 *       the plan change shifted the bottleneck
 *
 * CROSS-REFERENCE:
 *   - Match plan_line_id to the Id column in DBMS_XPLAN output
 *     (Section 3)
 *
 *   - Match plan_hash_value to Section 4
 *     (AWR summary)
 *     to correlate which plan performed better historically
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 15a:
ASH Plan Line Activity : Where Time Is Spent per Step
PROMPT

COL plan_hash_value FOR 9999999999 HEAD 'Plan Hash'
COL plan_line_id    FOR 999 HEAD 'Line'
COL plan_operation  FOR A30 HEAD 'Operation'
COL plan_options    FOR A20 HEAD 'Options'
COL object_name     FOR A30 HEAD 'Object'
COL event           FOR A40 HEAD 'Event'
COL ash_samples     FOR 999,999,999 HEAD 'ASH Samples'
COL pct_of_plan     FOR 990.99 HEAD '% of Plan'

WITH combined_ash AS (

    SELECT
        sql_plan_hash_value            AS plan_hash_value,
        sql_plan_line_id               AS plan_line_id,
        sql_plan_operation             AS plan_operation,
        sql_plan_options               AS plan_options,
        NVL(current_obj#,-1)           AS current_obj#,
        NVL(event,'ON CPU')            AS event,
        1                              AS weight

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND sql_plan_line_id IS NOT NULL
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        sql_plan_hash_value,
        sql_plan_line_id,
        sql_plan_operation,
        sql_plan_options,
        NVL(current_obj#,-1),
        NVL(event,'ON CPU'),
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND sql_plan_line_id IS NOT NULL
      AND '&&v_use_ash' = 'N'
),

plan_totals AS (

    SELECT
        plan_hash_value,
        SUM(weight) AS plan_total

    FROM combined_ash

    GROUP BY plan_hash_value
)

SELECT
    a.plan_hash_value,
    a.plan_line_id,
    a.plan_operation,
    a.plan_options,

    NVL(
        (SELECT o.object_name
         FROM dba_objects o
         WHERE o.object_id = a.current_obj#
           AND a.current_obj# > 0
           AND ROWNUM = 1),
        CASE
            WHEN a.current_obj# > 0
            THEN 'OBJ#'||a.current_obj#
        END
    ) AS object_name,

    a.event,

    SUM(a.weight)
        AS ash_samples,

    ROUND(
        SUM(a.weight) /
        NULLIF(MAX(pt.plan_total),0) * 100,
        2
    ) AS pct_of_plan

FROM combined_ash a

JOIN plan_totals pt
  ON pt.plan_hash_value = a.plan_hash_value

GROUP BY
    a.plan_hash_value,
    a.plan_line_id,
    a.plan_operation,
    a.plan_options,
    a.current_obj#,
    a.event,
    pt.plan_total

ORDER BY
    a.plan_hash_value,
    a.plan_line_id

FETCH FIRST 100 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 15b: ASH Plan Line Summary
 *              - Aggregated by Plan Step (No Event)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Compact view:
 * total time per plan line regardless of wait event.
 *
 * This gives a quick
 * "which step is the bottleneck"
 * answer without the event-level detail.
 *
 * Use Section 15a for drill-down.
 *
 * The cumulative_pct column shows a running total
 * — when it reaches ~80%,
 * you've found the steps responsible
 * for most of the time.
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 15b:
ASH Plan Line Summary : Top Steps per Plan Hash
PROMPT

COL plan_hash_value FOR 9999999999 HEAD 'Plan Hash'
COL plan_line_id    FOR 999 HEAD 'Line'
COL plan_operation  FOR A30 HEAD 'Operation'
COL plan_options    FOR A20 HEAD 'Options'
COL object_name     FOR A30 HEAD 'Object'
COL ash_samples     FOR 999,999,999 HEAD 'ASH Samples'
COL pct_of_plan     FOR 990.99 HEAD '% of Plan'
COL cumulative_pct  FOR 990.99 HEAD 'Cumul %'
COL top_wait        FOR A35 HEAD 'Top Wait Event'

WITH combined_ash AS (

    SELECT
        sql_plan_hash_value AS plan_hash_value,
        sql_plan_line_id    AS plan_line_id,
        sql_plan_operation  AS plan_operation,
        sql_plan_options    AS plan_options,
        NVL(current_obj#,-1) AS current_obj#,
        NVL(event,'ON CPU')  AS event,
        1                    AS weight

    FROM gv$active_session_history

    WHERE sql_id = '&&p_sql_id'
      AND sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND sql_plan_line_id IS NOT NULL
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        sql_plan_hash_value,
        sql_plan_line_id,
        sql_plan_operation,
        sql_plan_options,
        NVL(current_obj#,-1),
        NVL(event,'ON CPU'),
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND sql_plan_line_id IS NOT NULL
      AND '&&v_use_ash' = 'N'
),

line_agg AS (

    SELECT
        plan_hash_value,
        plan_line_id,
        plan_operation,
        plan_options,
        event,
        MAX(current_obj#) AS current_obj#,
        SUM(weight)       AS ash_samples

    FROM combined_ash

    GROUP BY
        plan_hash_value,
        plan_line_id,
        plan_operation,
        plan_options,
        event
),

line_summary AS (

    SELECT
        plan_hash_value,
        plan_line_id,

        MAX(plan_operation)
            AS plan_operation,

        MAX(plan_options)
            AS plan_options,

        MAX(current_obj#)
            KEEP (
                DENSE_RANK LAST
                ORDER BY ash_samples
            ) AS current_obj#,

        SUM(ash_samples)
            AS ash_samples,

        MAX(event)
            KEEP (
                DENSE_RANK LAST
                ORDER BY ash_samples
            ) AS top_wait

    FROM line_agg

    GROUP BY
        plan_hash_value,
        plan_line_id
),

plan_totals AS (

    SELECT
        plan_hash_value,
        SUM(ash_samples) AS plan_total

    FROM line_summary

    GROUP BY plan_hash_value
),

ranked AS (

    SELECT
        ls.plan_hash_value,
        ls.plan_line_id
        ls.plan_line_id,
        ls.plan_operation,
        ls.plan_options,
        ls.current_obj#,
        ls.ash_samples,

        ROUND(
            ls.ash_samples /
            NULLIF(pt.plan_total, 0) * 100,
            2
        ) AS pct_of_plan,

        SUM(ls.ash_samples)
            OVER (
                PARTITION BY ls.plan_hash_value
                ORDER BY ls.ash_samples DESC
                ROWS UNBOUNDED PRECEDING
            ) AS running_sum,

        pt.plan_total,
        ls.top_wait

    FROM line_summary ls

    JOIN plan_totals pt
      ON pt.plan_hash_value = ls.plan_hash_value
)

SELECT
    r.plan_hash_value,
    r.plan_line_id,
    r.plan_operation,
    r.plan_options,

    NVL(
        (SELECT o.object_name
         FROM dba_objects o
         WHERE o.object_id = r.current_obj#
           AND r.current_obj# > 0
           AND ROWNUM = 1),

        CASE
            WHEN r.current_obj# > 0
            THEN 'OBJ#'||r.current_obj#
        END

    ) AS object_name,

    r.ash_samples,
    r.pct_of_plan,

    ROUND(
        r.running_sum /
        NULLIF(r.plan_total, 0) * 100,
        2
    ) AS cumulative_pct,

    r.top_wait

FROM ranked r

ORDER BY
    r.plan_hash_value,
    r.ash_samples DESC

FETCH FIRST 80 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 8a: System-Wide Top 10 Wait Events
 *              (ASH, Analysis Window)
 *------------------------------------------------------------------
 * FOR THE LLM:
 *
 * This is the ENTIRE DATABASE wait profile
 * during the analysis window,
 * not filtered to the target SQL.
 *
 * Use it to determine whether the SQL's
 * performance issue is SQL-specific
 * or caused by a system-wide problem
 * (storage degradation,
 * interconnect saturation,
 * latch storms,
 * log file sync spikes, etc.).
 *
 * KEY ANALYSIS:
 *
 *   - If the database-wide top events
 *     match the target SQL's top events
 *     (from Section 2b),
 *     the problem is likely systemic,
 *     not plan-related
 *
 *   - High "log file sync" system-wide
 *       = commit bottleneck
 *         (redo log I/O)
 *
 *   - High "gc%" system-wide on RAC
 *       = interconnect saturation
 *         or cross-instance block shipping overload
 *         — affects ALL SQL
 *
 *   - High "cell single block physical read"
 *       on Exadata
 *       = storage cell latency
 *         or flash cache miss
 *
 *   - High "resmgr:cpu quantum"
 *       = Resource Manager
 *         is CPU-throttling many sessions,
 *         not just the target SQL
 *
 *   - Compare the target SQL's
 *     % of total DB time
 *     (from Section 2a)
 *     to see if it's a significant contributor
 *     or a victim
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 8a:
System-Wide Top 10 Wait Events (Analysis Window)
PROMPT

COL wait_class FOR A15 HEAD 'Wait Class'
COL event      FOR A45 HEAD 'Event'
COL ash_samples FOR 999,999,999 HEAD 'ASH Samples'
COL pct_db_time FOR 990.99 HEAD '% DB Time'
COL avg_wait_ms FOR 999,990.99 HEAD 'Avg Wait(ms)'

WITH combined_ash AS (

    SELECT
        NVL(wait_class,'ON CPU') AS wait_class,
        NVL(event,'ON CPU')      AS event,
        NVL(time_waited,0)       AS time_waited_us,
        1                        AS weight

    FROM gv$active_session_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        NVL(wait_class,'ON CPU'),
        NVL(event,'ON CPU'),
        NVL(time_waited,0),
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'N'
),

totals AS (
    SELECT SUM(weight) AS t
    FROM combined_ash
)

SELECT
    a.wait_class,
    a.event,

    SUM(a.weight)
        AS ash_samples,

    ROUND(
        SUM(a.weight) /
        NULLIF(MAX(t.t),0) * 100,
        2
    ) AS pct_db_time,

    ROUND(
        AVG(
            CASE
                WHEN a.time_waited_us > 0
                THEN a.time_waited_us
            END
        ) / 1000,
        2
    ) AS avg_wait_ms

FROM combined_ash a
CROSS JOIN totals t

GROUP BY
    a.wait_class,
    a.event

ORDER BY
    ash_samples DESC

FETCH FIRST 10 ROWS ONLY;

PROMPT

/*------------------------------------------------------------------
 * SECTION 8b: System-Wide Top Wait Classes Over Time (Hourly)
 *------------------------------------------------------------------
 * FOR THE LLM:
 *
 * Hourly time-series of database-wide wait classes.
 *
 * Compare to Section 2c
 * (SQL-specific hourly waits)
 * to see if contention spikes affecting the target SQL
 * coincide with database-wide spikes.
 *
 * If they do,
 * the root cause is systemic.
 *------------------------------------------------------------------*/

PROMPT
PROMPT ## SECTION 8b:
System-Wide Wait Classes Over Time (Hourly)
PROMPT

COL snap_hour     FOR A19 HEAD 'Snap Hour'
COL on_cpu        FOR 99,999,999 HEAD 'On CPU'
COL user_io       FOR 99,999,999 HEAD 'User I/O'
COL cluster_wait  FOR 99,999,999 HEAD 'Cluster'
COL concurrency   FOR 99,999,999 HEAD 'Concurrency'
COL commit_wait   FOR 99,999,999 HEAD 'Commit'
COL application   FOR 99,999,999 HEAD 'Application'
COL other_waits   FOR 99,999,999 HEAD 'Other'
COL total_samples FOR 99,999,999 HEAD 'Total'
COL aas           FOR 9,990.9 HEAD 'AAS'

WITH combined_ash AS (

    SELECT
        sample_time,
        NVL(wait_class,'ON CPU') AS wait_class,
        1                        AS weight

    FROM gv$active_session_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT
        sample_time,
        NVL(wait_class,'ON CPU'),
        10

    FROM dba_hist_active_sess_history

    WHERE sample_time BETWEEN &&v_begin_date_expr
                          AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND '&&v_use_ash' = 'N'
)

SELECT
    TO_CHAR(
        TRUNC(sample_time,'HH24'),
        'YYYY-MM-DD HH24:MI:SS'
    ) AS snap_hour,

    SUM(
        CASE
            WHEN wait_class = 'ON CPU'
            THEN weight
            ELSE 0
        END
    ) AS on_cpu,

    SUM(
        CASE
            WHEN wait_class = 'User I/O'
            THEN weight
            ELSE 0
        END
    ) AS user_io,

    SUM(
        CASE
            WHEN wait_class = 'Cluster'
            THEN weight
            ELSE 0
        END
    ) AS cluster_wait,

    SUM(
        CASE
            WHEN wait_class = 'Concurrency'
            THEN weight
            ELSE 0
        END
    ) AS concurrency,

    SUM(
        CASE
            WHEN wait_class = 'Commit'
            THEN weight
            ELSE 0
        END
    ) AS commit_wait,

    SUM(
        CASE
            WHEN wait_class = 'Application'
            THEN weight
            ELSE 0
        END
    ) AS application,

    SUM(
        CASE
            WHEN wait_class NOT IN (
                'ON CPU',
                'User I/O',
                'Cluster',
                'Concurrency',
                'Commit',
                'Application'
            )
            THEN weight
            ELSE 0
        END
    ) AS other_waits,

    SUM(weight)
        AS total_samples,

    ROUND(
        SUM(weight) / 3600,
        1
    ) AS aas

FROM combined_ash

GROUP BY
    TRUNC(sample_time,'HH24')

ORDER BY 1;

PROMPT

/*------------------------------------------------------------------
 * SECTION 8c: System-Wide Top 20 SQL by DB Time
 *              (Analysis Window)
 *------------------------------------------------------------------
 * FOR THE LLM:
 * Shows the top 20 SQL statements consuming the most DB time during the analysis window.
 * Use this to see where the target SQL ranks relative to other workload.
 * If the target SQL is #1, it's the primary driver.
 * If it's not in the top 10, the performance issue may be less impactful  than perceived,
 * or other SQL may be causing the contention affecting the target SQL.
 *------------------------------------------------------------------*/


PROMPT
PROMPT ## SECTION 8c: System-Wide Top 20 SQL by DB Time (Analysis Window)
PROMPT

COL rnk            FOR 99             HEAD '#'
COL sql_id         FOR A13            HEAD 'SQL ID'
COL is_target      FOR A3             HEAD '>>>'
COL ash_samples    FOR 999,999,999   HEAD 'ASH Samples'
COL pct_db_time    FOR 990.99         HEAD '% DB Time'
COL sql_text_trunc FOR A60            HEAD 'SQL Text (first 60 chars)' WORD_WRAP

WITH combined_ash AS (

    SELECT sql_id, 1 AS weight
    FROM gv$active_session_history
    WHERE sample_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND sql_id IS NOT NULL
      AND '&&v_use_ash' = 'Y'
      AND con_dbid = &&p_dbid

    UNION ALL

    SELECT sql_id, 10
    FROM dba_hist_active_sess_history
    WHERE sample_time BETWEEN &&v_begin_date_expr AND &&v_end_date_expr
      AND session_type = 'FOREGROUND'
      AND sql_id IS NOT NULL
      AND '&&v_use_ash' = 'N'
),

totals AS (
    SELECT SUM(weight) AS t
    FROM combined_ash
),

ranked AS (

    SELECT
        sql_id,

        SUM(weight)
            AS ash_samples,

        ROUND(
            SUM(weight) /
            NULLIF(MAX(t.t),0) * 100,
            2
        ) AS pct_db_time,

        ROW_NUMBER()
            OVER (
                ORDER BY SUM(weight) DESC
            ) AS rnk

    FROM combined_ash a,
         totals t

    GROUP BY sql_id, t.t
)

SELECT
    r.rnk,
    r.sql_id,

    CASE
        WHEN r.sql_id = '&&p_sql_id'
        THEN '>>>'
    END AS is_target,

    r.ash_samples,
    r.pct_db_time,

    (
        SELECT SUBSTR(sql_text,1,60)
        FROM gv$sql s
        WHERE s.sql_id = r.sql_id
          AND ROWNUM = 1
    ) AS sql_text_trunc

FROM ranked r

WHERE r.rnk <= 20

ORDER BY r.rnk;

SPOOL OFF

PROMPT
PROMPT Spool file written: &spool_file