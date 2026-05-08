-- ================================================================
-- Purpose: Generate a self-describing Oracle health snapshot for
--          on-call incident response (Oracle 19c+).
-- Input  : The script PROMPTS for a ServiceNow ticket number and
--          incident category.
-- Design : Output is pure evidence; Copilot instructions embedded
--          in the spool force a fresh, independent analysis each run.
-- Control: Diagnostics are evidence; Copilot output is advisory and
--          must be reviewed by a DBA before attachment.
-- Warning: No database changes are performed by this script.
-- updated 2026-05-07 09:00  -- v2.0 enhanced
-- ================================================================

SET LINESIZE 200
SET PAGESIZE 900
SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON

SPOOL oncall_copilot_health_check.log

-- ================================================================
-- Allowed Incident Categories
-- ================================================================
PROMPT === Allowed Ticket Categories ===
PROMPT - Hung / Stuck Workload
PROMPT - Performance Degradation
PROMPT - Blocking / Locking
PROMPT - Space / Capacity
PROMPT - Stats / Optimizer
PROMPT - ETL Structural Issue
PROMPT ================================
PROMPT

-- ================================================================
-- Required On-Call Metadata
-- ================================================================
ACCEPT service_now_ticket CHAR PROMPT 'Enter ServiceNow Ticket Number: '
ACCEPT ticket_category   CHAR PROMPT 'Enter Ticket Category: '

DEFINE service_now_ticket = '&service_now_ticket'
DEFINE ticket_category    = '&ticket_category'

PROMPT ============================================================
PROMPT On-Call Context
PROMPT ============================================================
PROMPT ServiceNow Ticket : &service_now_ticket
PROMPT Incident Category : &ticket_category
PROMPT Generated At      : &&_DATE
PROMPT ============================================================
PROMPT

-- ================================================================
-- COPILOT AUTO-INSTRUCTIONS – General (NO USER PROMPTING)
-- ================================================================
PROMPT ============================================================
PROMPT === COPILOT AUTO-INSTRUCTIONS (NO USER PROMPTING) ===
PROMPT ============================================================
PROMPT Treat this file ingestion as a NEW and INDEPENDENT analysis.
PROMPT Ignore all prior conversation, conclusions, or reports.
PROMPT You are acting as a senior ON-CALL ORACLE DBA ASSISTANT.
PROMPT Do NOT ask the user any questions.
PROMPT Do NOT request additional input.
PROMPT CONTEXT PROVIDED:
PROMPT - ServiceNow Ticket Number
PROMPT - Incident Category
PROMPT - Full Oracle diagnostic output
PROMPT REQUIRED ACTIONS:
PROMPT 1) Analyze the ENTIRE contents of this file from scratch.
PROMPT 2) Interpret diagnostics USING the Incident Category.
PROMPT 3) Apply the interpretation rules below.
PROMPT REQUIRED OUTPUTS:
PROMPT A) A short executive summary.
PROMPT B) A full on-call DBA report for ServiceNow.
PROMPT C) A numeric summary section that reports key counts and usage metrics.
PROMPT
PROMPT INTERPRETATION RULES:
PROMPT - PX Deq:* waits = parallel coordination, NOT blocking.
PROMPT - resmgr:cpu quantum = expected CPU throttling.
PROMPT - Internal MR/AE enqueues are NORMAL unless waits grow.
PROMPT - Multiversioned objects during APPEND/PARALLEL are EXPECTED.
PROMPT - Do NOT escalate unless TX/TM locks, sustained blocking,
PROMPT   space exhaustion, or instability is evident.
PROMPT - ACTIVE_PROCESSES represents Oracle process usage (foreground +
PROMPT   background) and MUST be used as the primary indicator of process
PROMPT   exhaustion risk.
PROMPT ANALYTICAL EXPECTATIONS:
PROMPT - Calculate totals, percentages, rates, and relative usage where possible.
PROMPT - Call out notable counts (e.g., number of blockers, sessions, locks).
PROMPT - Highlight sizes (GB, %, rates) and explain whether they are normal or risky.
PROMPT - Explicitly state WHY each key metric is healthy, degraded, or concerning.
PROMPT - When data is missing, say so explicitly rather than assuming.
PROMPT - Quantitative findings (including zero counts) are REQUIRED, not optional.
PROMPT
PROMPT ============================================================
PROMPT ESCALATION and VERDICT GUIDANCE (ADVISORY)
PROMPT ============================================================
PROMPT Use the following guidance to determine GREEN, YELLOW, or RED verdicts.
PROMPT These thresholds are ADVISORY and do NOT replace human DBA judgment.
PROMPT Copilot MUST explain WHY a condition meets the chosen verdict.
PROMPT VERDICT DEFINITIONS:
PROMPT - GREEN: Metrics within expected operating range; no immediate DBA action.
PROMPT - YELLOW: Metrics elevated, abnormal, or trending; monitor and prepare.
PROMPT - RED: Metrics indicate imminent or active risk requiring intervention.
PROMPT PROCESS CAPACITY (ACTIVE_PROCESSES vs MAX_PROCESSES):
PROMPT - GREEN: < 65% utilization with stable or declining trend.
PROMPT - YELLOW: 65%-85% utilization or sustained upward trend.
PROMPT - RED: > 85% utilization, rapid growth, or ORA-00020 risk symptoms.
PROMPT BLOCKING / LOCKING:
PROMPT - GREEN: No TX/TM blocking sessions detected.
PROMPT - YELLOW: Blocking present with wait times < 30 seconds and stable.
PROMPT - RED: TX/TM blocking with wait times > 60 seconds or increasing.
PROMPT RAC / GES ENQUEUES:
PROMPT - GREEN: No GES blocking enqueues.
PROMPT - YELLOW: Transient GES blocking without impact.
PROMPT - RED: Sustained GES blocking affecting multiple instances.
PROMPT REDO / CHECKPOINT BEHAVIOR:
PROMPT - GREEN: Redo rates consistent with workload; no recovery pressure.
PROMPT - YELLOW: Elevated redo without checkpoint or recovery impact.
PROMPT - RED: Redo causing checkpoint backlog or recovery risk.
PROMPT SPACE / CAPACITY (FRA, TEMP, TABLESPACES):
PROMPT - GREEN: < 75% of maximum capacity.
PROMPT - YELLOW: 75%-90% of capacity or fast growth observed.
PROMPT - RED: > 90%, autoextend exhausted, or imminent allocation failure.
PROMPT MEMORY STABILITY:
PROMPT - GREEN: No ORA-4031 events or repeated allocation failures.
PROMPT - YELLOW: Fragmentation or allocation pressure without errors.
PROMPT - RED: ORA-4031 errors or repeated allocation failures detected.
PROMPT ETL CONTEXT OVERRIDES:
PROMPT - High CPU, redo, TEMP, or PX utilization ALONE does not imply YELLOW or RED.
PROMPT - Escalate ONLY when ETL activity causes blocking, errors,
PROMPT   space exhaustion, or instability.
PROMPT
PROMPT ============================================================
PROMPT === EXADATA CPU SATURATION INTERPRETATION RULE ===
PROMPT ============================================================
PROMPT When CDB-level CPU over-subscription is confirmed
PROMPT (DB TIME > DB CPU across instances), and Resource Manager is active,
PROMPT PDB-level performance degradation must be treated as a downstream
PROMPT effect of container-level enforcement.
PROMPT Do NOT attribute CPU starvation to a single PDB or SQL when CDB-level
PROMPT saturation is evident.
PROMPT ============================================================

-- ======================  BEGIN DIAGNOSTICS  ======================

PROMPT ============================================================
PROMPT === SECTION 1 : DATABASE IDENTIFICATION ===
PROMPT ============================================================

SET LINESIZE 130

SELECT name || ' om:' || open_mode || ' res:' || restricted ||
       ' ot:' || open_time ||
       ' ts:' || total_size/1024/1024/1024 ||
       ' guid:' || guid "pdb info"
  FROM v$pdbs;

SET LINESIZE 100

SELECT 'instance: ' || instance_name ||
       ' #:' || instance_number ||
       ' on ' || host_name ||
       ' ' || TO_CHAR(startup_time,'mm/dd/yyyy hh24:mi') ||
       ' ' || logins ||
       ' version:' || version_full ||
       ' ' || parallel "instance info"
  FROM v$instance;

SELECT 'PDB Environment: ' ||
       CASE
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'D' THEN 'Development'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'B' THEN 'BCP'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'T' THEN 'ADP Test Master'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'U' THEN 'UAT'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'S' THEN 'Test'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'P' THEN 'Production'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'E' THEN 'Pre-Production'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'F' THEN 'Prodfix'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'N' THEN 'Training'
           WHEN UPPER(SUBSTR(p.name,1,1)) = 'L' THEN 'Lab'
           ELSE 'Unknown environment'
       END pdb_environment
  FROM v$pdbs p
 WHERE name NOT LIKE '%SEED%';

SELECT 'Datacenter Host location: ' ||
       CASE
           WHEN SUBSTR(i.host_name,6,1) = 'b' THEN 'Oxmoor (OX)'
           WHEN SUBSTR(i.host_name,6,1) = 'v' THEN 'Shoreview (SV)'
           WHEN SUBSTR(i.host_name,6,1) = 'c' THEN 'CIC (CIC)'
           WHEN SUBSTR(i.host_name,6,1) = 'i' THEN 'Silas'
           WHEN SUBSTR(i.host_name,6,1) = 'l' THEN 'St. Louis STL'
           WHEN SUBSTR(i.host_name,6,1) = 'z' THEN 'Tempe'
           WHEN SUBSTR(i.host_name,6,1) = 'w' THEN 'WEC'
           WHEN SUBSTR(i.host_name,6,1) = 'g' THEN 'Garland'
           WHEN SUBSTR(i.host_name,6,1) = 'e' THEN 'Lewisville'
           WHEN SUBSTR(i.host_name,6,1) = 's' THEN 'Sterling'
           WHEN SUBSTR(i.host_name,6,1) = 'm' THEN 'Manassas'
           ELSE 'Unknown environment'
       END host_environment
  FROM v$instance i;

SELECT 'Instance Environment: ' ||
       CASE
           WHEN SUBSTR(i.instance_name,1,1) = 'p' THEN 'Production'
           WHEN SUBSTR(i.instance_name,1,1) = 'b' THEN 'BCP'
           WHEN SUBSTR(i.instance_name,1,1) = 'u' THEN 'Non-Prod'
           WHEN SUBSTR(i.instance_name,1,1) = 'l' THEN 'Lab'
           ELSE 'Unknown environment'
       END instance_environment
  FROM v$instance i;

PROMPT ============================================================
PROMPT === SECTION 2 : CHECKPOINT AND REDO STATISTICS ===
PROMPT ============================================================

PROMPT
PROMPT === Checkpoint Statistics ===
SELECT inst_id, name, value
  FROM gv$sysstat
 WHERE name LIKE '%checkpoint%'
 ORDER BY inst_id, name;

PROMPT
PROMPT === Redo Log Switches (Last Hour) ===
SELECT inst_id,
       COUNT(*) AS switches_last_hour
  FROM gv$log_history
 WHERE first_time > SYSDATE - 1/24
 GROUP BY inst_id;

PROMPT ============================================================
PROMPT === SECTION 3 : BLOCKING / LOCKING ===
PROMPT ============================================================

PROMPT
PROMPT === Blocking Sessions ===
SELECT a.inst_id,
       a.sid,
       a.serial#,
       a.username,
       a.status,
       a.sql_id,
       b.blocking_session,
       b.blocking_instance,
       b.event,
       b.seconds_in_wait
  FROM gv$session a
  JOIN gv$session b
    ON a.sid = b.sid
   AND a.inst_id = b.inst_id
 WHERE b.blocking_session IS NOT NULL;

PROMPT
PROMPT === Enqueue Locks Held (Filtered) ===
SELECT l.inst_id,
       l.sid,
       s.serial#,
       s.username,
       s.program,
       l.type,
       l.id1,
       l.id2,
       l.lmode,
       l.request,
       l.block
  FROM gv$lock l
  JOIN gv$session s
    ON l.sid = s.sid
   AND l.inst_id = s.inst_id
 WHERE l.block > 0
   AND l.lmode IN (4, 5, 6)
   AND l.type NOT IN ('CF', 'IR', 'IS', 'ST')
 ORDER BY l.inst_id, l.sid;

PROMPT
PROMPT === GES Blocking Enqueues (RAC Only) ===
SELECT inst_id,
       resource_name1,
       resource_name2,
       state,
       owner_node,
       blocked,
       blocker
  FROM gv$ges_blocking_enqueue
 WHERE blocker = 1;

PROMPT ============================================================
PROMPT === SECTION 4 : BACKGROUND PROCESS STATUS ===
PROMPT ============================================================

PROMPT
PROMPT === Background Process Status (CKPT, DBWR, LGWR) ===
SELECT inst_id,
       name,
       description,
       paddr
  FROM gv$bgprocess
 WHERE name IN ('CKPT', 'DBWR', 'LGWR');

SHOW PARAMETER check
SHOW PARAMETER mttr
SHOW PARAMETER inter

PROMPT
PROMPT === Instance Recovery Info ===
SELECT inst_id,
       recovery_estimated_ios,
       actual_redo_blks
  FROM gv$instance_recovery;

PROMPT ============================================================
PROMPT === SECTION 5 : SUMMARY REPORT (Processes, FRA) ===
PROMPT ============================================================

SET PAGESIZE 100
SET LINESIZE 200

COLUMN DB_NAME FORMAT A20
COLUMN TIMESTAMP FORMAT A30
COLUMN ACTIVE_PROCESSES FORMAT 9,999
COLUMN MAX_PROCESSES FORMAT 999,999
COLUMN PROCESS_USAGE FORMAT 999.99
COLUMN FRA_TOTAL_GB FORMAT 99,999.99
COLUMN FRA_USED_GB FORMAT 99,999.99
COLUMN FRA_USAGE FORMAT 999.99

PROMPT
PROMPT === Summary Report ===
SET HEADING ON

SELECT
    SYS_CONTEXT('USERENV','DB_NAME') AS DB_NAME,
    TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS TIMESTAMP,
    (SELECT COUNT(*) FROM v$process) AS ACTIVE_PROCESSES,
    TO_NUMBER((SELECT VALUE FROM v$parameter WHERE NAME = 'processes')) AS MAX_PROCESSES,
    ROUND(
        (SELECT COUNT(*) FROM v$process) /
        TO_NUMBER((SELECT VALUE FROM v$parameter WHERE NAME = 'processes')) * 100,
        2
    ) AS PROCESS_USAGE,
    ROUND(SPACE_LIMIT / 1024 / 1024 / 1024, 2) AS FRA_TOTAL_GB,
    ROUND(SPACE_USED / 1024 / 1024 / 1024, 2) AS FRA_USED_GB,
    ROUND(SPACE_USED / SPACE_LIMIT * 100, 2) AS FRA_USAGE
  FROM v$recovery_file_dest;

PROMPT ============================================================
PROMPT === SECTION 5b : ARCHIVE LOG STATUS AND GAP SUMMARY ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: Count archive logs generated in the last
PROMPT 24 hours per thread. Flag if any dest_id shows a GAP status.
PROMPT Treat missing rows as "no archive generation" (green).
PROMPT

SELECT thread#,
       dest_id,
       COUNT(*) AS archives_last_24h,
       MAX(sequence#) AS max_sequence
  FROM gv$archived_log
 WHERE first_time > SYSDATE - 1
 GROUP BY thread#, dest_id
 ORDER BY thread#, dest_id;

PROMPT
PROMPT If GAP_STATUS contains non-null values below, escalate to YELLOW.
PROMPT
SELECT * FROM gv$archive_gap;

PROMPT ============================================================
PROMPT === SECTION 5c : RMAN BACKUP STATUS ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: Report the status of the most recent
PROMPT full/incremental backup per input_type. A failed or MISSING
PROMPT backup within the expected window is YELLOW/RED.
PROMPT
SET LINESIZE 200

SELECT TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
       input_type,
       status,
       ROUND(elapsed_seconds/60,1) AS elapsed_min,
       ROUND(input_bytes/1024/1024/1024,2) AS input_gb,
       ROUND(output_bytes/1024/1024/1024,2) AS output_gb,
       output_device_type
  FROM v$rman_backup_job_details
 WHERE start_time > SYSDATE - 7
 ORDER BY start_time DESC;

PROMPT ============================================================
PROMPT === SECTION 6 : ACTIVE SESSION HISTORY – WAIT CLASSES ===
PROMPT ============================================================

PROMPT
PROMPT COPILOT_AUTO_INSTRUCT: The ASH samples below cover the LAST HOUR.
PROMPT Focus on non-idle wait classes. Treat high User I/O samples as
PROMPT expected for ETL/scan workloads unless accompanied by blocking.
PROMPT
SELECT wait_class,
       COUNT(*) samples,
       ROUND(COUNT(*) / 10 / 3600, 2) est_seconds
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND session_state = 'WAITING'
   AND wait_class <> 'Idle'
 GROUP BY wait_class
 ORDER BY samples DESC;

PROMPT ============================================================
PROMPT === SECTION 7 : MEMORY STABILITY ===
PROMPT ============================================================

PROMPT
PROMPT === ORA-4031 Detection ===
SELECT originating_timestamp,
       message_text
  FROM v$diag_alert_ext
 WHERE message_text LIKE '%ORA-4031%';

PROMPT
PROMPT === User I/O Wait Events (Last Hour) ===
SELECT event,
       COUNT(*) samples
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND wait_class = 'User I/O'
 GROUP BY event
 ORDER BY samples DESC;

PROMPT
PROMPT === Top SQL by User I/O Samples (Last Hour) ===
SELECT sql_id,
       COUNT(*) samples
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND wait_class = 'User I/O'
 GROUP BY sql_id
 ORDER BY samples DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT === Memory Parameters ===
SELECT name, value, isdefault
  FROM v$parameter
 WHERE name IN (
    'shared_pool_size',
    'shared_pool_reserved_size',
    'large_pool_size',
    'sga_target',
    'pga_aggregate_target',
    'memory_target'
);

PROMPT
PROMPT === PGA / UGA / Memory Statistics ===
SELECT name, value
  FROM v$sysstat
 WHERE name IN (
    'failed allocations',
    'free memory',
    'session uga memory max',
    'session uga memory',
    'session pga memory',
    'session pga memory max'
);

PROMPT
PROMPT === Large SGA Allocations (> 10 MB) ===
SELECT pool, name, bytes
  FROM v$sgastat
 WHERE bytes > 10000000
 ORDER BY bytes DESC;

PROMPT
PROMPT === Shared Pool Reserved Stats ===
SELECT
    REQUESTS,
    REQUEST_FAILURES,
    LAST_FAILURE_SIZE,
    ABORTED_REQUESTS
  FROM v$shared_pool_reserved;

PROMPT
PROMPT === SGA Dynamic Components ===
SELECT component,
       current_size,
       min_size,
       max_size
  FROM v$sga_dynamic_components
 WHERE component IN (
    'shared pool',
    'large pool',
    'java pool',
    'buffer cache'
);

PROMPT
PROMPT === Shared Pool Free Memory ===
SELECT pool,
       name,
       bytes
  FROM v$sgastat
 WHERE pool = 'shared pool'
   AND name LIKE '%free memory%'
 ORDER BY bytes DESC;

PROMPT
PROMPT === DB Object Cache Usage (top sharable memory) ===
SELECT type,
       COUNT(*) AS count,
       SUM(sharable_mem)/1024/1024 AS total_mb
  FROM v$db_object_cache
 WHERE sharable_mem > 100000
 GROUP BY type
 ORDER BY total_mb DESC;

PROMPT
PROMPT === Large Pool Parameter ===
SELECT name, value, isdefault
  FROM v$parameter
 WHERE name = 'large_pool_size';

PROMPT
PROMPT === Hidden: _PX_use_large_pool ===
SELECT name, value
  FROM v$parameter
 WHERE name = '_PX_use_large_pool';

PROMPT
PROMPT === Large Pool Usage ===
SELECT pool, name, bytes
  FROM v$sgastat
 WHERE pool = 'large pool'
 ORDER BY bytes DESC;

PROMPT ============================================================
PROMPT === SECTION 8 : SESSION COUNTS ===
PROMPT ============================================================

PROMPT
PROMPT === Active Sessions (All Types) ===
SELECT inst_id,
       COUNT(*) AS active_sessions
  FROM gv$session
 WHERE status = 'ACTIVE'
 GROUP BY inst_id
 ORDER BY inst_id;

PROMPT
PROMPT === Active USER Sessions ===
SELECT inst_id,
       COUNT(*) AS active_user_sessions
  FROM gv$session
 WHERE status = 'ACTIVE'
   AND type = 'USER'
 GROUP BY inst_id
 ORDER BY inst_id;

PROMPT ============================================================
PROMPT === SECTION 9 : ACTIVE SESSION DETAILS ===
PROMPT ============================================================

PROMPT
PROMPT === Active Session Snapshot ===
SELECT DISTINCT(
    s.username || ' : ' ||
    TO_CHAR(s.logon_time,'mm/dd/yyyy hh24:mi') || ' : ' ||
    s.program || ' : ' ||
    s.terminal || ' : ' ||
    s.sid || ':' ||
    SUBSTR(t.sql_text,1,20) || ' PL:' ||
    PLSQL_ENTRY_OBJECT_ID || ' : ' ||
    s.serial# || ',' ||
    s.inst_id || ' : ' ||
    s.state || ' : ' ||
    TO_CHAR(s.SQL_EXEC_START,'mm/dd/yyyy hh24:mi') || ' : ' ||
    s.event || ' : ' ||
    s.wait_class || ' : ' ||
    s.sql_id || ' : ' ||
    s.status || ' sqlstart:' ||
    TO_CHAR(s.SQL_EXEC_START,'mm/dd/yyyy hh24:mi') || ' : ' ||
    s.BLOCKING_SESSION || ' : ' ||
    s.BLOCKING_INSTANCE ||
    s.wait_time || ' : ' ||
    s.BLOCKING_SESSION_STATUS || ' : ' ||
    s.module
)
  FROM gv$session s,
       gv$sql t
 WHERE s.sql_id = t.sql_id
   AND s.username IS NOT NULL
   AND s.status = 'ACTIVE'
   AND t.sql_id = s.sql_id
 ORDER BY 1;

PROMPT ============================================================
PROMPT === SECTION 10 : LONG-RUNNING OPERATIONS (Data Pump) ===
PROMPT ============================================================

SET LINESIZE 200
SET PAGESIZE 999
SET ECHO OFF

PROMPT
PROMPT === V$SESSION_LONGOPS ===
SELECT
    b.username || ' : ' ||
    a.sid || ' : ' ||
    b.opname || ' : ' ||
    b.target || ' : ' ||
    ROUND(b.SOFAR*100/(b.TOTALWORK+0.001),0) || '% done : ' ||
    b.TIME_REMAINING || ' : ' ||
    TO_CHAR(b.start_time,'YYYY/MM/DD HH24:MI:SS') "longops"
  FROM gv$session_longops b,
       gv$session a
 WHERE a.sid = b.sid
 ORDER BY 1;

PROMPT
PROMPT === Data Pump Jobs (by SID) ===
SELECT
    s1.sid || ' ' ||
    s1.serial# || ' ' ||
    s1.sofar || ' ' ||
    s1.totalwork || ' ' ||
    dp.owner_name || ' ' ||
    dp.state || ' ' ||
    dp.job_mode "totalwork"
  FROM gv$session_longops s1,
       gv$datapump_job dp
 WHERE s1.opname = dp.job_name
   AND s1.sofar != s1.totalwork;

PROMPT
PROMPT === Data Pump Workers with Time Remaining ===
SELECT
    x.job_name || ' ' ||
    b.state || ' ' ||
    b.job_mode || ' ' ||
    b.degree || ' ' ||
    x.owner_name || ' ' ||
    SUBSTR(z.sql_text,1,20) || ' ' ||
    p.message || ' ' ||
    p.totalwork || ' ' ||
    p.sofar || ' ' ||
    ROUND((p.sofar/p.totalwork)*100,2) || ' ' ||
    p.time_remaining AS LONGOPS
  FROM dba_datapump_jobs b
  LEFT JOIN dba_datapump_sessions x ON (x.job_name = b.job_name)
  LEFT JOIN gv$session y ON (y.saddr = x.saddr)
  LEFT JOIN gv$sql z ON (y.sql_id = z.sql_id)
  LEFT JOIN gv$session_longops p ON (p.sql_id = y.sql_id)
 WHERE y.module='Data Pump Worker'
   AND p.time_remaining > 0;

SET FEEDBACK ON

PROMPT
PROMPT === Data Pump Sessions ===
SELECT
    'owner:' || owner_name ||
    ' job_name:' || job_name ||
    ' inst:' || inst_id ||
    ' sess_type:' || session_type ||
    ' saddr:' || saddr "pump sessions"
  FROM dba_datapump_sessions;

PROMPT ============================================================
PROMPT === SECTION 11 : TABLESPACE SPACE ===
PROMPT ============================================================

SET VERIFY OFF
SET LINESIZE 160

PROMPT
PROMPT === UNDO and TEMP Tablespace Usage ===
SELECT
    tablespace_name || ' : ' ||
    used_percent "TABLESPACE SPACE"
  FROM dba_tablespace_usage_metrics
 WHERE (
    tablespace_name LIKE UPPER('%UNDO%')
    OR tablespace_name LIKE UPPER('%TEMP%')
);

PROMPT
PROMPT === All Tablespace Usage ===
SELECT TRUNC(SYSDATE) asof_dt,
       df.tablespace_name tablespace_name,
       MAX(df.autoextensible) auto_ext,
       ROUND(df.maxbytes / (1024 * 1024), 0) max_ts_size,
       ROUND((df.bytes - SUM(fs.bytes)) / (df.maxbytes) * 100, 0) max_ts_pct_used,
       ROUND(df.bytes / (1024 * 1024), 0) curr_ts_size,
       ROUND((df.bytes - SUM(fs.bytes)) / (1024 * 1024), 0) used_ts_size,
       ROUND((df.bytes-SUM(fs.bytes)) * 100 / df.bytes, 0) ts_pct_used,
       SUM(fs.bytes) / (1024 * 1024) free_ts_size,
       NVL(ROUND(SUM(fs.bytes) * 100 / df.bytes), 0) ts_pct_free
  FROM dba_free_space fs,
       (
        SELECT tablespace_name,
               SUM(bytes) bytes,
               SUM(DECODE(maxbytes, 0, bytes, maxbytes)) maxbytes,
               MAX(autoextensible) autoextensible
          FROM dba_data_files
         GROUP BY tablespace_name
       ) df
 WHERE fs.tablespace_name (+) = df.tablespace_name
 GROUP BY df.tablespace_name, df.bytes, df.maxbytes
UNION ALL
SELECT TRUNC(SYSDATE) asof_dt,
       df.tablespace_name tablespace_name,
       MAX(df.autoextensible) auto_ext,
       ROUND(df.maxbytes / (1024 * 1024), 0) max_ts_size,
       ROUND((df.bytes - SUM(fs.bytes)) / (df.maxbytes) * 100, 0) max_ts_pct_used,
       ROUND(df.bytes / (1024 * 1024), 0) curr_ts_size,
       ROUND((df.bytes - SUM(fs.bytes)) / (1024 * 1024), 0) used_ts_size,
       ROUND((df.bytes-SUM(fs.bytes)) * 100 / df.bytes, 0) ts_pct_used,
       SUM(fs.bytes) / (1024 * 1024) free_ts_size,
       NVL(ROUND(SUM(fs.bytes) * 100 / df.bytes), 0) ts_pct_free
  FROM (
        SELECT tablespace_name,
               bytes_free,
               bytes_used
          FROM v$temp_space_header
       ) fs,
       (
        SELECT tablespace_name,
               SUM(bytes) bytes,
               SUM(DECODE(maxbytes, 0, bytes, maxbytes)) maxbytes,
               MAX(autoextensible) autoextensible
          FROM dba_temp_files
         GROUP BY tablespace_name
       ) df
 WHERE fs.tablespace_name (+) = df.tablespace_name
 GROUP BY df.tablespace_name, df.bytes, df.maxbytes
 ORDER BY 4 DESC;

PROMPT
PROMPT === Temp Tablespace Detail ===
SELECT
    tf.tablespace_name,
    ROUND(SUM(tf.bytes_used) / 1024 / 1024 / 1024, 2) AS used_gb,
    ROUND(SUM(tf.bytes_free) / 1024 / 1024 / 1024, 2) AS free_gb,
    ROUND(SUM(tf.bytes_used + tf.bytes_free) / 1024 / 1024 / 1024, 2) AS current_size_gb,
    ROUND(SUM(df.maxbytes) / 1024 / 1024 / 1024, 2) AS max_size_gb,
    ROUND(SUM(tf.bytes_used) / SUM(df.maxbytes) * 100, 2) AS pct_used_of_max
  FROM v$temp_space_header tf
  JOIN dba_temp_files df
    ON tf.tablespace_name = df.tablespace_name
   AND tf.file_id = df.file_id
 GROUP BY tf.tablespace_name
 ORDER BY pct_used_of_max DESC;

PROMPT ============================================================
PROMPT === SECTION 12 : BLOCKING SESSION CHAIN ===
PROMPT ============================================================

COLUMN username FORMAT a15
COLUMN BI FORMAT 9999
COLUMN when FORMAT a14

SET LINESIZE 240

PROMPT
PROMPT === Blocking Session Details ===
SELECT
    s.username,
    s.sid,
    s.inst_id,
    s.event,
    s.sql_id,
    s.SECONDS_IN_WAIT,
    s.BLOCKING_SESSION_STATUS,
    s.blocking_session,
    s.BLOCKING_INSTANCE BI,
    t.sql_id,
    TO_CHAR(t.sql_exec_start,'mm/dd hh24:mi') when
  FROM gv$session s,
       gv$session t
 WHERE s.blocking_session IS NOT NULL
   AND t.sid = s.blocking_session
   AND t.inst_id = s.blocking_instance;

PROMPT ============================================================
PROMPT === SECTION 13 : ALERT LOG (Last 100 lines, last 24h) ===
PROMPT ============================================================

PROMPT
PROMPT === Alert Log (Last 100 Entries, Last Day) ===
SELECT *
  FROM (
    SELECT
        ORIGINATING_TIMESTAMP || ' : ' ||
        MESSAGE_TYPE || ' : ' ||
        MESSAGE_ID || ' : ' ||
        MESSAGE_TEXT AS "Alert log"
      FROM V$DIAG_ALERT_EXT
     WHERE ORIGINATING_TIMESTAMP > SYSDATE - 1
     ORDER BY ORIGINATING_TIMESTAMP DESC
)
 WHERE ROWNUM <= 100
 ORDER BY 1;

PROMPT ============================================================
PROMPT === SECTION 14 : CDB CPU SATURATION ===
PROMPT ============================================================

PROMPT
PROMPT COPILOT_AUTO_INSTRUCT: The authoritative CDB CPU saturation
PROMPT metric is CPU_WAIT_SEC = DB_TIME_SEC - DB_CPU_SEC.
PROMPT - CPU_WAIT_SEC = 0 => GREEN (no CPU contention)
PROMPT - CPU_WAIT_SEC small and stable => YELLOW
PROMPT - CPU_WAIT_SEC large or growing => RED (CDB CPU saturated)
PROMPT
SELECT
    inst_id,
    ROUND(SUM(CASE WHEN stat_name = 'DB time' THEN value END) / 1e6, 2) AS db_time_sec,
    ROUND(SUM(CASE WHEN stat_name = 'DB CPU' THEN value END) / 1e6, 2) AS db_cpu_sec,
    ROUND(
        (SUM(CASE WHEN stat_name = 'DB time' THEN value END) -
         SUM(CASE WHEN stat_name = 'DB CPU' THEN value END)) / 1e6, 2
    ) AS cpu_wait_sec
  FROM gv$sys_time_model
 GROUP BY inst_id
 ORDER BY inst_id;

PROMPT
PROMPT === CDB CPU Capacity (cpu_count per instance) ===
SELECT inst_id,
       value AS cpu_count
  FROM gv$parameter
 WHERE name = 'cpu_count'
 ORDER BY inst_id;

PROMPT
PROMPT === Active Resource Manager Plan ===
SELECT inst_id,
       name,
       is_top_plan,
       cpu_managed,
       utilization_limit
  FROM gv$rsrc_plan
 WHERE is_top_plan = 'TRUE'
 ORDER BY inst_id;

PROMPT ============================================================
PROMPT === SECTION 15 : EXADATA STORAGE HEALTH (PDB View) ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: Evaluate Exadata cell wait events from
PROMPT inside the PDB. Smart Scan and Flash Cache events indicate
PROMPT healthy offload. Absence during scan-heavy workload is RED.
PROMPT
SELECT event,
       total_waits,
       time_waited
  FROM v$system_event
 WHERE event LIKE 'cell%';

PROMPT ============================================================
PROMPT === SECTION 16 : LOCK ANALYSIS (Objects and Blockers) ===
PROMPT ============================================================

SET LINESIZE 200 PAGESIZE 666

BREAK ON Kill ON username ON terminal

COLUMN Kill heading 'Kill String' format a13
COLUMN res heading 'Resource Type' format 999
COLUMN id1 format 9999990
COLUMN id2 format 9999990
COLUMN lmode heading 'Lock Held' format a25
COLUMN request heading 'Lock Requested' format a25
COLUMN serial# format 99999
COLUMN username format a25 heading "Username"
COLUMN terminal heading Term format a22
COLUMN tab format a35 heading "Table Name"
COLUMN sub format a35 heading "Sub Name"
COLUMN owner format a9
COLUMN Address format a18
COLUMN ctime format 999999999 heading "Seconds"

PROMPT
PROMPT === Lock Details ===
SELECT
    NVL(S.USERNAME,'Internal') username,
    s.machine || '@' || s.terminal terminal,
    L.SID || ',' || S.SERIAL# || '@' || s.inst_id Kill,
    U1.username || '.' || SUBSTR(T1.NAME,1,25) tab,
    subname sub,
    DECODE(
        L.LMODE,
        1,'No Lock',
        2,'Row Share',
        3,'Row Exclusive',
        4,'Share',
        5,'Share Row Exclusive',
        6,'Exclusive',
        null
    ) lmode,
    DECODE(
        L.REQUEST,
        1,'No Lock',
        2,'Row Share',
        3,'Row Exclusive',
        4,'Share',
        5,'Share Row Exclusive',
        6,'Exclusive',
        null
    ) request,
    l.ctime
  FROM gv$lock L,
       gv$session S,
       SYS.dba_users U1,
       SYS.obj$ T1
 WHERE L.SID = S.SID
   AND T1.OBJ# = DECODE(L.ID2,0,L.ID1,L.ID2)
   AND U1.USER# = T1.OWNER#
   AND S.TYPE != 'BACKGROUND'
 ORDER BY 1,2,5;

PROMPT ============================================================
PROMPT === SECTION 17 : SGA / MEMORY RESIZE HISTORY ===
PROMPT ============================================================

SHOW PARAMETER pga
SHOW PARAMETER pool

COLUMN component FORMAT a25
COLUMN Initial FORMAT 99,999,999,999
COLUMN Final   FORMAT 99,999,999,999
COLUMN Started FORMAT A25

PROMPT
PROMPT === SGA Resize Operations (last 800) ===
SELECT
    COMPONENT,
    OPER_TYPE,
    INITIAL_SIZE "Initial",
    FINAL_SIZE "Final",
    TO_CHAR(start_time,'dd-mon hh24:mi:ss') Started
  FROM V$SGA_RESIZE_OPS;

PROMPT
PROMPT === Memory Resize Operations ===
SELECT
    COMPONENT,
    OPER_TYPE,
    INITIAL_SIZE "Initial",
    FINAL_SIZE "Final",
    TO_CHAR(start_time,'dd-mon hh24:mi:ss') Started
  FROM V$MEMORY_RESIZE_OPS;

PROMPT ============================================================
PROMPT === SECTION 18 : INVALID OBJECTS ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: Count invalid objects by owner.
PROMPT 0 = GREEN; small number of known exceptions = YELLOW;
PROMPT growing/unknown invalids = investigate (YELLOW/RED).
PROMPT
SELECT owner,
       object_type,
       COUNT(*) AS invalid_count
  FROM dba_objects
 WHERE status = 'INVALID'
   AND owner NOT IN ('SYS','SYSTEM','XDB','ORDDATA','ORDSYS',
                     'MDSYS','OLAPSYS','EXFSYS','WKSYS','CTXSYS')
 GROUP BY owner, object_type
 ORDER BY owner, object_type;

PROMPT
PROMPT COPILOT_AUTO_INSTRUCT: Total invalid objects (excluding Oracle maintained).
PROMPT Report the sum in the numeric summary.
PROMPT
SELECT COUNT(*) AS total_invalid_objects
  FROM dba_objects
 WHERE status = 'INVALID'
   AND owner NOT IN ('SYS','SYSTEM','XDB','ORDDATA','ORDSYS',
                     'MDSYS','OLAPSYS','EXFSYS','WKSYS','CTXSYS');

PROMPT ============================================================
PROMPT === SECTION 19 : FAILED SCHEDULER JOBS (Last 24h) ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: Flag any FAILED scheduler jobs in the
PROMPT last 24 hours. Count them by job name. A single known failure
PROMPT may be YELLOW; repeated or unexpected failures are RED.
PROMPT
SELECT owner,
       job_name,
       status,
       TO_CHAR(log_date,'YYYY-MM-DD HH24:MI:SS') AS log_date
  FROM dba_scheduler_job_run_details
 WHERE log_date > SYSDATE - 1
   AND status = 'FAILED'
 ORDER BY log_date DESC;

PROMPT ============================================================
PROMPT === SECTION 20 : RAC INTERCONNECT HEALTH ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: On RAC, check for interconnect waits.
PROMPT 'gc cr/current block busy' or 'gc buffer busy acquire'
PROMPT samples indicate global cache contention. Show top 5 events.
PROMPT If no rows: single-instance (green).
PROMPT
SELECT event,
       COUNT(*) samples
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 1/24
   AND event LIKE 'gc%'
 GROUP BY event
 ORDER BY samples DESC
 FETCH FIRST 5 ROWS ONLY;

PROMPT ============================================================
PROMPT === SECTION 21 : REAL-TIME SQL MONITOR (Top 10) ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: The following SQL statements are
PROMPT currently monitored (executing or recently completed).
PROMPT Focus on statements consuming high CPU, I/O, or TEMP.
PROMPT NULL TEMP_SPACE_ALLOCATED means no TEMP spill (green).
PROMPT Large TEMP spill should be noted.
PROMPT
SELECT sql_id,
       sql_exec_id,
       status,
       elapsed_time,
       cpu_time,
       user_io_wait_time,
       application_wait_time,
       concurrency_wait_time,
       cluster_wait_time,
       buffer_gets,
       disk_reads,
       direct_writes,
       ROUND(temp_space_allocated/1024/1024,2) AS temp_mb
  FROM v$sql_monitor
 WHERE status IN ('EXECUTING','DONE')
   AND (cpu_time + user_io_wait_time) > 0
 ORDER BY elapsed_time DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT ============================================================
PROMPT === SECTION 22 : DATA GUARD STATUS (Snapshot) ===
PROMPT ============================================================

PROMPT COPILOT_AUTO_INSTRUCT: V$DATAGUARD_STATS provides transport
PROMPT and apply lag. Missing view = not a Data Guard config (green).
PROMPT apply_lag > 0 => YELLOW; growing apply lag => RED.
PROMPT
SELECT name,
       value,
       time_computed
  FROM v$dataguard_stats;

PROMPT ============================================================
PROMPT === SECTION 23 : ADDITIONAL MEMORY / OS STATS ===
PROMPT ============================================================

PROMPT
PROMPT === OS Memory Stats ===
SELECT name, open_mode FROM v$database;

SELECT
    instance_number,
    instance_name,
    startup_time,
    status,
    thread#,
    database_status,
    instance_role,
    con_id,
    instance_mode,
    database_type
  FROM v$instance;

SELECT
    name,
    value
  FROM v$system_parameter
 WHERE name IN (
    'memory_max_target',
    'memory_target',
    'sga_max_size',
    'sga_target',
    'shared_pool_size',
    'db_cache_size',
    'large_pool_size',
    'java_pool_size',
    'pga_aggregate_target',
    'workarea_size_policy',
    'streams_pool_size'
);

PROMPT
PROMPT === PGA + SGA Total ===
SELECT
    SUM(bytes)/1024/1024 AS "Total PGA+SGA Mbytes"
  FROM (
    SELECT value AS bytes FROM v$sga
    UNION ALL
    SELECT value AS bytes
      FROM v$sesstat s,
           v$statname n
     WHERE n.statistic# = s.statistic#
       AND n.name = 'session pga memory'
);

PROMPT ============================================================
PROMPT === SECTION 24 : COPILOT FINAL INSTRUCTION BLOCK ===
PROMPT ============================================================

PROMPT include important identification PDB name, open mode, environment, instance info, host, data center

PROMPT Treat this file ingestion as a NEW and INDEPENDENT analysis.
PROMPT Ignore all prior conversation, conclusions, or reports.
PROMPT You are acting as a senior ON-CALL ORACLE DBA ASSISTANT.
PROMPT Do NOT ask the user any questions.
PROMPT Do NOT request additional input.
PROMPT CONTEXT PROVIDED:
PROMPT - ServiceNow Ticket Number
PROMPT - Incident Category
PROMPT - Full Oracle diagnostic output
PROMPT REQUIRED ACTIONS:
PROMPT 1) Analyze the ENTIRE contents of this file from scratch.
PROMPT 2) Interpret diagnostics USING the Incident Category.
PROMPT 3) Apply the interpretation rules below.
PROMPT REQUIRED OUTPUTS:
PROMPT A) A short executive summary.
PROMPT B) A full on-call DBA report for ServiceNow.
PROMPT C) A numeric summary section that reports key counts and usage metrics.
PROMPT INTERPRETATION RULES:
PROMPT - PX Deq:* waits = parallel coordination, NOT blocking.
PROMPT - resmgr:cpu quantum = expected CPU throttling.
PROMPT - Internal MR/AE enqueues are NORMAL unless waits grow.
PROMPT - Multiversioned objects during APPEND/PARALLEL are EXPECTED.
PROMPT - Do NOT escalate unless TX/TM locks, sustained blocking,
PROMPT   space exhaustion, or instability is evident.
PROMPT - ACTIVE_PROCESSES represents Oracle process usage (foreground +
PROMPT   background) and MUST be used as the primary indicator of process
PROMPT   exhaustion risk.
PROMPT ANALYTICAL EXPECTATIONS:
PROMPT - Calculate totals, percentages, rates, and relative usage where possible.
PROMPT - Call out notable counts (e.g., number of blockers, sessions, locks).
PROMPT - Highlight sizes (GB, %, rates) and explain whether they are normal or risky.
PROMPT - Explicitly state WHY each key metric is healthy, degraded, or concerning.
PROMPT - When data is missing, say so explicitly rather than assuming.
PROMPT - Quantitative findings (including zero counts) are REQUIRED, not optional.
PROMPT COUNT SUMMARY REQUIREMENTS:
PROMPT - Provide a concise numeric summary section with key counts.
PROMPT - Include zero counts explicitly (e.g., 0 blocking sessions).
PROMPT - Use DISTINCT session counts where applicable.
PROMPT - Use ACTIVE_PROCESSES for process capacity, not session counts.
PROMPT - Do not infer counts from queries that do not support them.
PROMPT If verdict is GREEN, explicitly state:
PROMPT "No immediate DBA action required."

PROMPT === Done Collecting Diagnostics ===

SPOOL OFF

-- ============================================================
-- ON-CALL DBA FINAL STEPS
-- ============================================================

PROMPT =========================================================
PROMPT === ON-CALL DBA FINAL STEPS ===
PROMPT =========================================================
PROMPT
PROMPT 1) Start a new session with Copilot and then Drag and drop the file:
PROMPT     oncall_copilot_health_check.log
PROMPT     into Copilot.
PROMPT
PROMPT 2) Allow Copilot to complete its analysis.
PROMPT
PROMPT 3) Then issue this instruction to Copilot:
PROMPT
PROMPT Create a physical text file artifact using the file-creation tool.
PROMPT Write the entire on-call DBA report into the file.
PROMPT Name the file using this format oncall_copilot_report_<ServiceNowTicket>.txt
PROMPT and return it as a downloadable attachment.
PROMPT
PROMPT 4) Save the generated file and attach BOTH files
PROMPT     to the ServiceNow ticket.
PROMPT
PROMPT =========================================================
PROMPT === SCRIPT COMPLETE ===
PROMPT =========================================================

EXIT