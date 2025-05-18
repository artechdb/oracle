#!/bin/bash

# ========== CONFIGURATION ==========
ORACLE_USER="system"
ORACLE_PASS="your_password"
ORACLE_SID="ORCL"
EMAIL_TO="dba-team@example.com"
EMAIL_SUBJECT="Oracle RAC Health Check Report - $(date '+%Y-%m-%d %H:%M')"
HTML_REPORT="./output/health_check_$(date +%Y%m%d_%H%M%S).html"
DB_CONNECT_STRING="$ORACLE_USER/$ORACLE_PASS@$ORACLE_SID"

# ========== ANALYSIS WINDOWS ==========
DAYS_AGO=7
HOURS_AGO=1
MINUTES_AGO=5

# ========== THRESHOLDS ==========
MAX_SESSIONS_UTIL=90
MAX_PROCESSES_UTIL=90
DB_LOAD_THRESHOLD=85
MAX_BLOCKED_SESSIONS=0
MAX_IO_RESP_MS=20

# ========== FUNCTIONS ==========
init_html_report() {
    cat templates/report_header.html > "$HTML_REPORT"
    echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"
    echo "<p>Generated on: $(date)</p>" >> "$HTML_REPORT"
}

close_html_report() {
    cat templates/report_footer.html >> "$HTML_REPORT"
}

append_section() {
    local title="$1"
    echo "<h2>$title</h2><pre>" >> "$HTML_REPORT"
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    append_section "$title"
    sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
}

send_email_report() {
    if command -v mailx &>/dev/null; then
        cat "$HTML_REPORT" | mailx -a "Content-type: text/html" -s "$EMAIL_SUBJECT" "$EMAIL_TO"
    else
        echo "mailx not found. Please install or configure an alternative mail agent."
    fi
}

# ========== INDIVIDUAL CHECK FUNCTIONS ==========
run_check_db_load() { run_sql_file_report "DB Load" "sql/01_db_load.sql"; }
run_check_active_sessions() { run_sql_file_report "Active/Inactive Sessions" "sql/02_active_sessions.sql"; }
run_check_session_processes() { run_sql_file_report "Session & Process Utilization" "sql/03_sessions_processes.sql"; }
run_check_sga_pga_usage() { run_sql_file_report "SGA & PGA Usage" "sql/04_sga_pga_usage.sql"; }
run_check_blocking_sessions() { run_sql_file_report "Blocking Sessions" "sql/05_blocking_sessions.sql"; }
run_check_long_running_sessions() { run_sql_file_report "Long Running Sessions" "sql/06_long_running_sessions.sql"; }
run_check_io_response_time() { run_sql_file_report "IO Response Time" "sql/07_io_response_time.sql"; }
run_check_wait_events() { run_sql_file_report "Wait Events (1 Hour & 5 Min)" "sql/08_wait_events_window.sql"; }
run_check_rac_instance_skew() { run_sql_file_report "RAC Instance Load Skew" "sql/09_rac_instance_skew.sql"; }
run_check_top_waits() { run_sql_file_report "Top Wait Events by Instance" "sql/10_top_waits_by_instance.sql"; }
run_check_global_cache() { run_sql_file_report "Global Cache Statistics" "sql/11_global_cache_stats.sql"; }
run_check_top_sql() { run_sql_file_report "Top SQL by Elapsed Time" "sql/12_top_sql_elapsed.sql"; }
run_check_tablespace_usage() { run_sql_file_report "Tablespace Usage" "sql/13_tablespace_usage.sql"; }
run_check_asm_usage() { run_sql_file_report "ASM Diskgroup Usage" "sql/14_asm_diskgroup_usage.sql"; }
run_check_log_sync() { run_sql_file_report "Redo Log Sync Waits" "sql/15_log_sync_contention.sql"; }
run_check_temp_usage() { run_sql_file_report "Temp Usage" "sql/16_temp_usage.sql"; }
run_check_parse_ratio() { run_sql_file_report "Parse to Execute Ratio" "sql/17_parse_to_exec_ratio.sql"; }
run_check_log_switches() { run_sql_file_report "Log Switch History" "sql/18_log_switch_history.sql"; }
run_check_fra_usage() { run_sql_file_report "FRA Space Usage" "sql/19_fra_usage.sql"; }
run_check_ashtop_5min() { run_sql_file_report "ASH Top - Last 5 Min" "sql/20_ashtop_5min.sql"; }
run_check_ashtop_1hr() { run_sql_file_report "ASH Top - Last 1 Hour" "sql/21_ashtop_1hr.sql"; }

# ========== MAIN ==========
main() {
    init_html_report

    run_check_db_load
    run_check_active_sessions
    run_check_session_processes
    run_check_sga_pga_usage
    run_check_blocking_sessions
    run_check_long_running_sessions
    run_check_io_response_time
    run_check_wait_events
    run_check_rac_instance_skew
    run_check_top_waits
    run_check_global_cache
    run_check_top_sql
    run_check_tablespace_usage
    run_check_asm_usage
    run_check_log_sync
    run_check_temp_usage
    run_check_parse_ratio
    run_check_log_switches
    run_check_fra_usage
    run_check_ashtop_5min
    run_check_ashtop_1hr

    close_html_report
    send_email_report
}

main

#!/bin/bash

DB_CONNECT_STRING="$1"
HTML_REPORT="health_check_report.html"
SQL_DIR="./sql"

DAYS_AGO=1
HOURS_AGO=1
MINUTES_AGO=5

is_exadata() {
  echo "Checking for Exadata platform..."
  if sqlplus -s "$DB_CONNECT_STRING" <<EOF | grep -q "Exadata"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT platform_name FROM v$database WHERE platform_name LIKE '%Exadata%';
EXIT;
EOF
  then
    echo "✅ Exadata platform detected"
    return 0
  else
    echo "❌ Not an Exadata system"
    return 1
  fi
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    local connect_str="$3"

    local tmp_output=$(mktemp)
    local section_status="OK"

    sqlplus -s "$connect_str" <<EOF > "$tmp_output"
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF
SET VERIFY OFF
DEFINE DAYS_AGO=$DAYS_AGO
DEFINE HOURS_AGO=$HOURS_AGO
DEFINE MINUTES_AGO=$MINUTES_AGO
@$sql_file
EXIT
EOF

    if grep -q 'CRITICAL' "$tmp_output"; then
        section_status="<span style='color:red;'><b>CRITICAL</b></span>"
    elif grep -q 'WARNING' "$tmp_output"; then
        section_status="<span style='color:orange;'><b>WARNING</b></span>"
    else
        section_status="<span style='color:green;'><b>OK</b></span>"
    fi

    echo "<h2>$title - Status: $section_status</h2><pre>" >> "$HTML_REPORT"

    while IFS= read -r line; do
        if echo "$line" | grep -q 'CRITICAL'; then
            line=$(echo "$line" | sed 's/CRITICAL/<span style="color:red;"><b>CRITICAL<\/b><\/span>/g')
        elif echo "$line" | grep -q 'WARNING'; then
            line=$(echo "$line" | sed 's/WARNING/<span style="color:orange;"><b>WARNING<\/b><\/span>/g')
        elif echo "$line" | grep -q 'OK'; then
            line=$(echo "$line" | sed 's/OK/<span style="color:green;"><b>OK<\/b><\/span>/g')
        fi
        echo "$line" >> "$HTML_REPORT"
    done < "$tmp_output"

    rm -f "$tmp_output"
    echo "</pre>" >> "$HTML_REPORT"
}

echo "<html><head><title>Oracle RAC Health Check</title></head><body>" > "$HTML_REPORT"
echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"

# Example modules
run_sql_file_report "DB Load (AAS)" "$SQL_DIR/01_db_load.sql" "$DB_CONNECT_STRING"
run_sql_file_report "Long Running Sessions" "$SQL_DIR/06_long_running_sessions.sql" "$DB_CONNECT_STRING"
run_sql_file_report "IO Response Time" "$SQL_DIR/07_io_response_time.sql" "$DB_CONNECT_STRING"

if is_exadata; then
  run_sql_file_report "Exadata Offload Efficiency" "$SQL_DIR/35_exadata_offload_efficiency.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Cell Interconnect Waits" "$SQL_DIR/36_exadata_cell_interconnect_waits.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Flash Cache Stats" "$SQL_DIR/37_exadata_flashcache_stats.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Smart Scan Usage" "$SQL_DIR/38_exadata_smart_scan_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "ASM Diskgroup Status" "$SQL_DIR/39_exadata_asm_diskgroup_status.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "Exadata Wait Class Usage" "$SQL_DIR/40_exadata_wait_class_usage.sql" "$DB_CONNECT_STRING"
  run_sql_file_report "IORM Plan Check" "$SQL_DIR/41_exadata_iorm_plan.sql" "$DB_CONNECT_STRING"
fi

echo "</body></html>" >> "$HTML_REPORT"
# ========== CONFIGURATION ==========
ORACLE_USER="system"
ORACLE_PASS="your_password"
ORACLE_SID="ORCL"
EMAIL_TO="dba-team@example.com"
EMAIL_SUBJECT="Oracle RAC Health Check Report - $(date '+%Y-%m-%d %H:%M')"
HTML_REPORT="./output/health_check_$(date +%Y%m%d_%H%M%S).html"
DB_CONNECT_STRING="$ORACLE_USER/$ORACLE_PASS@$ORACLE_SID"

# ========== ANALYSIS WINDOWS ==========
DAYS_AGO=7
HOURS_AGO=1
MINUTES_AGO=5

# ========== THRESHOLDS ==========
MAX_SESSIONS_UTIL=90
MAX_PROCESSES_UTIL=90
DB_LOAD_THRESHOLD=85
MAX_BLOCKED_SESSIONS=0
MAX_IO_RESP_MS=20

# ========== FUNCTIONS ==========
init_html_report() {
    cat templates/report_header.html > "$HTML_REPORT"
    echo "<h1>Oracle RAC Health Check Report</h1>" >> "$HTML_REPORT"
    echo "<p>Generated on: $(date)</p>" >> "$HTML_REPORT"
}

close_html_report() {
    cat templates/report_footer.html >> "$HTML_REPORT"
}

append_section() {
    local title="$1"
    echo "<h2>$title</h2><pre>" >> "$HTML_REPORT"
}

run_sql_file_report() {
    local title="$1"
    local sql_file="$2"
    append_section "$title"
    sqlplus -s "$DB_CONNECT_STRING" @"$sql_file" >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
}

send_email_report() {
    if command -v mailx &>/dev/null; then
        cat "$HTML_REPORT" | mailx -a "Content-type: text/html" -s "$EMAIL_SUBJECT" "$EMAIL_TO"
    else
        echo "mailx not found. Please install or configure an alternative mail agent."
    fi
}

# ========== MAIN ==========
main() {
    init_html_report

    for file in sql/*.sql; do
        title=$(basename "$file" .sql | sed 's/^[0-9]*_//; s/_/ /g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
        run_sql_file_report "$title" "$file"
    done

    close_html_report
    send_email_report
}

main
#
01_db_load.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN aas FORMAT 999.99
COLUMN db_time_mins FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === DATABASE LOAD (AAS BASED ON DB TIME IN MINUTES) - ORACLE 19C RAC ===

WITH db_time_data AS (
  SELECT s.snap_id,
         s.instance_number,
         s.begin_interval_time,
         s.end_interval_time,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END) AS db_time
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name
    FROM gv$instance
)
SELECT TO_CHAR(d.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       i.instance_name,
       ROUND(d.db_time / 1000000 / 60, 2) AS db_time_mins,
       ROUND((d.db_time / 1000000 / 60) /
             (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) AS aas,
       CASE
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) > 4 THEN 'CRITICAL'
         WHEN ROUND((d.db_time / 1000000 / 60) /
                    (EXTRACT(SECOND FROM (d.end_interval_time - d.begin_interval_time) DAY TO SECOND) / 60), 2) > 2 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM db_time_data d
  LEFT JOIN instance_names i ON d.instance_number = i.instance_number
 ORDER BY d.begin_interval_time DESC, i.instance_name;
<html>
<head>
  <title>Oracle RAC Health Check Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
    h1, h2 { color: #2c3e50; }
    pre { background-color: #fff; padding: 10px; border: 1px solid #ccc; overflow: auto; }
  </style>
</head>
<body>

 02_active_sessions.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sample_time FORMAT A20
COLUMN instance FORMAT 99
COLUMN service_name FORMAT A20
COLUMN session_type FORMAT A15
COLUMN status FORMAT A10
COLUMN active_count FORMAT 99999
COLUMN inactive_count FORMAT 99999

PROMPT === ACTIVE / INACTIVE SESSIONS BY SERVICE NAME (LAST &DAYS_AGO DAYS) - ORACLE 19C RAC ===

SELECT service_hash,
       service_name,
       instance_number AS instance,
       session_type,
       COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) AS active_count,
       COUNT(CASE WHEN session_state = 'CACHED' OR session_state = 'INACTIVE' THEN 1 END) AS inactive_count,
       CASE
         WHEN COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) > 80 THEN 'CRITICAL'
         WHEN COUNT(CASE WHEN session_state = 'ON CPU' OR session_state = 'WAITING' THEN 1 END) > 20 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - &DAYS_AGO
 GROUP BY service_hash, service_name, instance_number, session_type
 ORDER BY instance, service_name;
 03_sessions_processes.sql
 04_sga_pga_usage.sql
 05_blocking_sessions.sql
 06_long_running_sessions.sql
 07_io_response_time.sql
 08_wait_events_window.sql
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sample_time FORMAT A20
COLUMN event FORMAT A40
COLUMN wait_class FORMAT A20
COLUMN instance FORMAT 99
COLUMN count FORMAT 99999
COLUMN status FORMAT A10

PROMPT === TOP WAIT EVENTS (LAST &MINUTES_AGO MINUTES AND &HOURS_AGO HOURS) - ORACLE 19C RAC ===

-- Top events in the last &MINUTES_AGO minutes
PROMPT
PROMPT --- Wait Events (Last &MINUTES_AGO Minutes) ---

SELECT event,
       wait_class,
       instance_number AS instance,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 100 THEN 'CRITICAL'
         WHEN COUNT(*) > 50 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE CAST(sample_time AS DATE) >= SYSDATE - (&MINUTES_AGO / (24 * 60))
 GROUP BY event, wait_class, instance_number
 ORDER BY count DESC
FETCH FIRST 10 ROWS ONLY;

-- Top events in the last &HOURS_AGO hours
PROMPT
PROMPT --- Wait Events (Last &HOURS_AGO Hours) ---

SELECT event,
       wait_class,
       instance_number AS instance,
       COUNT(*) AS count,
       CASE
         WHEN COUNT(*) > 500 THEN 'CRITICAL'
         WHEN COUNT(*) > 200 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM gv$active_session_history
 WHERE CAST(sample_time AS DATE) >= SYSDATE - (&HOURS_AGO / 24)
 GROUP BY event, wait_class, instance_number
 ORDER BY count DESC
FETCH FIRST 10 ROWS ONLY;
09_rac_instance_skew.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN begin_time FORMAT A20
COLUMN instance_name FORMAT A20
COLUMN db_time_per_cpu FORMAT 999999.99
COLUMN io_mb FORMAT 999999.99
COLUMN status FORMAT A10

PROMPT === INSTANCE SKEW (PER-CPU LOAD & I/O) - ORACLE 19C RAC ===

WITH workload AS (
  SELECT s.snap_id,
         s.begin_interval_time,
         s.instance_number,
         MAX(CASE WHEN tm.stat_name = 'DB time' THEN tm.value END)/1000000 AS db_time_secs
    FROM dba_hist_sys_time_model tm
    JOIN dba_hist_snapshot s
      ON tm.snap_id = s.snap_id
     AND tm.instance_number = s.instance_number
   WHERE s.begin_interval_time > SYSDATE - &DAYS_AGO
     AND tm.stat_name = 'DB time'
   GROUP BY s.snap_id, s.begin_interval_time, s.instance_number
),
io_stats AS (
  SELECT snap_id,
         instance_number,
         SUM(CASE WHEN stat_name IN ('physical read bytes', 'physical write bytes') THEN value ELSE 0 END)/1024/1024 AS io_mb
    FROM dba_hist_sysstat
   WHERE stat_name IN ('physical read bytes', 'physical write bytes')
   GROUP BY snap_id, instance_number
),
cpu_cores AS (
  SELECT instance_number, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
),
instance_names AS (
  SELECT DISTINCT instance_number, instance_name FROM gv$instance
),
combined AS (
  SELECT w.snap_id,
         w.begin_interval_time,
         w.instance_number,
         w.db_time_secs,
         i.io_mb,
         c.cpu_count,
         ROUND(w.db_time_secs / c.cpu_count, 2) AS db_time_per_cpu
    FROM workload w
    JOIN cpu_cores c ON w.instance_number = c.instance_number
    LEFT JOIN io_stats i ON w.snap_id = i.snap_id AND w.instance_number = i.instance_number
)
SELECT TO_CHAR(c.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS begin_time,
       n.instance_name,
       c.db_time_per_cpu,
       ROUND(c.io_mb, 2) AS io_mb,
       CASE
         WHEN c.db_time_per_cpu > (SELECT AVG(db_time_per_cpu) * 1.5 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.db_time_per_cpu > (SELECT AVG(db_time_per_cpu) * 1.2 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         WHEN c.io_mb > (SELECT AVG(io_mb) * 1.5 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'CRITICAL'
         WHEN c.io_mb > (SELECT AVG(io_mb) * 1.2 FROM combined WHERE begin_interval_time = c.begin_interval_time) THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM combined c
  LEFT JOIN instance_names n ON c.instance_number = n.instance_number
 ORDER BY c.begin_interval_time DESC, n.instance_name;
 10_top_waits_by_instance.sql
 11_global_cache_stats.sql
 12_top_sql_elapsed.sql
 13_tablespace_usage.sql
 14_asm_diskgroup_usage.sql
15_log_sync_contention.sql
16_temp_usage.sql
17_parse_to_exec_ratio.sql
18_log_switch_history.sql
19_fra_usage.sql
22
SET PAGESIZE 100
SET LINESIZE 200
COLUMN originating_timestamp FORMAT A30
COLUMN message_text FORMAT A100
COLUMN inst_id FORMAT 99
COLUMN status FORMAT A10

PROMPT === ORA- ERRORS IN ALERT LOG (LAST 3 HOURS) - ORACLE 19C RAC ===

SELECT inst_id,
       TO_CHAR(CAST(originating_timestamp AS DATE), 'YYYY-MM-DD HH24:MI:SS') AS originating_timestamp,
       message_text,
       CASE
         WHEN LOWER(message_text) LIKE '%ora-%' THEN 'CRITICAL'
         ELSE 'OK'
       END AS status
  FROM gv$diag_alert_ext
 WHERE CAST(originating_timestamp AS DATE) > SYSDATE - 3/24
   AND LOWER(message_text) LIKE '%ora-%'
 ORDER BY originating_timestamp DESC;
 23
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN sid FORMAT 99999
COLUMN serial# FORMAT 99999
COLUMN username FORMAT A15
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20
COLUMN status FORMAT A10

PROMPT === DATABASE OBJECT LOCKING DETAILS (GV$LOCK + DBA_OBJECTS) ===

SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       o.object_name,
       o.object_type,
       CASE
         WHEN l.lmode IN (4, 5, 6) THEN 'LOCKED'
         ELSE 'REQUEST'
       END AS status
  FROM gv$session s
  JOIN gv$lock l ON s.sid = l.sid AND s.inst_id = l.inst_id
  JOIN dba_objects o ON l.id1 = o.object_id
 WHERE s.username IS NOT NULL
   AND l.type = 'TX'
 ORDER BY s.inst_id, s.sid;
32_sga_pga_advisory.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN target_mb FORMAT 99999
COLUMN est_extra_rw_mb FORMAT 99999.99
COLUMN est_cache_hit FORMAT 999.99
COLUMN advice FORMAT A10

PROMPT === PGA TARGET ADVICE (Oracle 19c) ===
SELECT ROUND(pga_target_for_estimate / 1024 / 1024) AS target_mb,
       ROUND(estd_extra_bytes_rw / 1024 / 1024, 2) AS est_extra_rw_mb,
       estd_pga_cache_hit_percentage AS est_cache_hit,
       CASE
         WHEN estd_pga_cache_hit_percentage >= 99 THEN 'OK'
         WHEN estd_pga_cache_hit_percentage >= 90 THEN 'WARNING'
         ELSE 'CRITICAL'
       END AS advice
  FROM v$pga_target_advice
 WHERE estd_pga_cache_hit_percentage IS NOT NULL
 ORDER BY target_mb;

PROMPT
PROMPT === SGA TARGET ADVICE (Oracle 19c) ===
SELECT ROUND(sga_size / 1024) AS target_mb,
       estd_db_time / 100 AS est_db_time_seconds,
       estd_physical_reads,
       CASE
         WHEN estd_db_time <=
              MIN(estd_db_time) OVER () THEN 'OK'
         WHEN estd_db_time <=
              MIN(estd_db_time) OVER () * 1.1 THEN 'WARNING'
         ELSE 'CRITICAL'
       END AS advice
  FROM v$sga_target_advice
 WHERE sga_size_factor BETWEEN 0.5 AND 2
 ORDER BY sga_size;
 
34_top_sql_cpu.sql
SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN executions FORMAT 9999999
COLUMN cpu_time FORMAT 9999999.99
COLUMN avg_cpu FORMAT 999999.99
COLUMN module FORMAT A20

PROMPT === TOP 5 SQLs BY CPU TIME ===
SELECT *
  FROM (
    SELECT sql_id,
           executions_delta AS executions,
           cpu_time_delta/1000000 AS cpu_time,
           ROUND((cpu_time_delta/1000000)/NULLIF(executions_delta, 0), 2) AS avg_cpu,
           module
      FROM dba_hist_sqlstat
     WHERE executions_delta > 0
     ORDER BY cpu_time_delta DESC
  )
WHERE ROWNUM <= 5;
42
SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN cpu_count FORMAT 99
COLUMN aas FORMAT 999.99
COLUMN status FORMAT A10

PROMPT === REAL-TIME AAS (GV$ACTIVE_SESSION_HISTORY, LAST &MINUTES_AGO MINUTES) ===

WITH active_sessions AS (
  SELECT inst_id,
         COUNT(*) / (&MINUTES_AGO * 60) AS aas
    FROM gv$active_session_history
   WHERE sample_time > SYSDATE - (&MINUTES_AGO / 1440)
     AND session_type = 'FOREGROUND'
   GROUP BY inst_id
),
cpu_cores AS (
  SELECT instance_number AS inst_id, MAX(value) AS cpu_count
    FROM dba_hist_osstat
   WHERE stat_name = 'NUM_CPUS'
   GROUP BY instance_number
)
SELECT a.inst_id,
       c.cpu_count,
       ROUND(a.aas, 2) AS aas,
       CASE
         WHEN a.aas > c.cpu_count THEN 'CRITICAL'
         WHEN a.aas > c.cpu_count * 0.75 THEN 'WARNING'
         ELSE 'OK'
       END AS status
  FROM active_sessions a
  JOIN cpu_cores c ON a.inst_id = c.inst_id
 ORDER BY a.inst_id;
 49
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN inst_id FORMAT 99
COLUMN sid FORMAT 99999
COLUMN serial# FORMAT 99999
COLUMN username FORMAT A15
COLUMN type FORMAT A10
COLUMN mode_held FORMAT A20
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A20

PROMPT === DDL OBJECT LOCKS (GV$LOCK + DBA_OBJECTS) ===

SELECT s.inst_id,
       s.sid,
       s.serial#,
       s.username,
       l.type,
       DECODE(l.lmode,
              0, 'None',
              1, 'Null',
              2, 'Row-S (SS)',
              3, 'Row-X (SX)',
              4, 'Share',
              5, 'S/Row-X (SSX)',
              6, 'Exclusive', 'Other') AS mode_held,
       o.object_name,
       o.object_type
  FROM gv$session s
  JOIN gv$lock l ON s.sid = l.sid AND s.inst_id = l.inst_id
  JOIN dba_objects o ON l.id1 = o.object_id
 WHERE l.type IN ('TM', 'DL')
   AND s.username IS NOT NULL
 ORDER BY s.inst_id, s.sid;

 38
 SET PAGESIZE 100
SET LINESIZE 200
COLUMN sql_id FORMAT A15
COLUMN sql_text FORMAT A50
COLUMN elapsed_time FORMAT 999999.99
COLUMN io_interconnect_bytes FORMAT 999999999
COLUMN status FORMAT A10

PROMPT === EXADATA SMART SCAN USAGE (RECENT SQLS) ===

SELECT sql_id,
       SUBSTR(sql_text, 1, 50) AS sql_text,
       elapsed_time / 1000000 AS elapsed_time,
       io_interconnect_bytes,
       CASE
         WHEN io_interconnect_bytes > 0 THEN 'OK'
         ELSE 'WARNING'
       END AS status
  FROM v$sql_monitor
 WHERE io_interconnect_bytes IS NOT NULL
   AND last_refresh_time > SYSDATE - 1/24
 ORDER BY last_refresh_time DESC
FETCH FIRST 10 ROWS ONLY;
