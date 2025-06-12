determine_primary_cdb() {
    local input_conn="$1"
    local html_file="$2"
    local primary_conn=""
    local db_role=""
    local primary_host=""
    local primary_port=""
    local primary_service=""

    echo "<div class='section'>" >> "$html_file"
    echo "<h2>Primary CDB Determination</h2>" >> "$html_file"

    # Get database role and configuration
    db_info=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT 'ROLE=' || database_role || '|FAL_SERVER=' || NVL(fal_server, 'NONE') || '|DG_BROKER=' || 
       (SELECT CASE WHEN COUNT(*) > 0 THEN 'ACTIVE' ELSE 'INACTIVE' END 
        FROM v\$parameter WHERE name = 'dg_broker_start' AND value = 'TRUE')
FROM v\$database;
EOF
    )

    # Parse database info
    IFS='|' read -r role_part fal_part broker_part <<< "$db_info"
    db_role=$(echo "$role_part" | cut -d'=' -f2)
    fal_server=$(echo "$fal_part" | cut -d'=' -f2)
    dg_broker=$(echo "$broker_part" | cut -d'=' -f2)

    case $db_role in
        "PRIMARY")
            echo "<p class='ok'>✅ Connected database is already PRIMARY</p>" >> "$html_file"
            primary_conn="$input_conn"
            ;;
        "PHYSICAL STANDBY")
            echo "<p class='info'>🔍 Connected to STANDBY database</p>" >> "$html_file"
            
            # Try Data Guard Broker first
            if [ "$dg_broker" = "ACTIVE" ]; then
                echo "<p class='info'>🔍 Checking Data Guard Broker configuration</p>" >> "$html_file"
                broker_config=$(sqlplus -s /nolog << EOF
connect $input_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT db_unique_name || '|' || hostname || '|' || db_domain 
FROM v\$dg_broker_config 
WHERE type = 'DATABASE' AND role = 'PRIMARY';
EOF
                )
                IFS='|' read -r primary_name primary_host primary_domain <<< "$broker_config"
                primary_service="${primary_name}.${primary_domain}"
                primary_port="1521"  # Default port for broker
            fi

            # Fallback to FAL_SERVER
            if [ -z "$primary_host" ] && [ "$fal_server" != "NONE" ]; then
                echo "<p class='info'>🔍 Using FAL_SERVER: $fal_server</p>" >> "$html_file"
                
                # Try to resolve FAL_SERVER from tnsnames.ora
                tns_entry=$(cat $ORACLE_HOME/network/admin/tnsnames.ora | grep -i "^$fal_server\s*=")
                
                # Parse TNS entry
                primary_host=$(echo "$tns_entry" | sed -n 's/.*HOST\s*=\s*\([^)]*\).*/\1/p' | head -1)
                primary_port=$(echo "$tns_entry" | sed -n 's/.*PORT\s*=\s*\([0-9]*\).*/\1/p' | head -1)
                primary_service=$(echo "$tns_entry" | sed -n 's/.*SERVICE_NAME\s*=\s*\([^)]*\).*/\1/p' | head -1)
                
                # Fallback to direct parsing if tnsnames.ora not accessible
                if [ -z "$primary_host" ]; then
                    primary_host=$(echo "$fal_server" | cut -d':' -f1)
                    primary_port=$(echo "$fal_server" | cut -d':' -f2 | cut -d'/' -f1)
                    primary_service=$(echo "$fal_server" | cut -d'/' -f2)
                fi
            fi

            # Validate results
            if [ -n "$primary_host" ] && [ -n "$primary_service" ]; then
                primary_port=${primary_port:-1521}  # Default port if not found
                primary_conn="sys@\"$primary_host:$primary_port/$primary_service\" as sysdba"
                echo "<p class='ok'>✅ Discovered primary CDB connection</p>" >> "$html_file"
                echo "<table>
                        <tr><th>Parameter</th><th>Value</th></tr>
                        <tr><td>Host</td><td>$primary_host</td></tr>
                        <tr><td>Port</td><td>$primary_port</td></tr>
                        <tr><td>Service</td><td>$primary_service</td></tr>
                      </table>" >> "$html_file"
            else
                echo "<p class='critical'>❌ Failed to determine primary CDB</p>" >> "$html_file"
                echo "<pre>Debug info:
                DG Broker Status: $dg_broker
                FAL_SERVER: $fal_server
                Broker Config: $broker_config
                Parsed Host: $primary_host
                Parsed Port: $primary_port
                Parsed Service: $primary_service</pre>" >> "$html_file"
                return 1
            fi

            # Verify primary connection
            verify_primary=$(sqlplus -s /nolog << EOF
connect $primary_conn
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT database_role FROM v\$database;
EOF
            )

            if [[ "$verify_primary" == *"PRIMARY"* ]]; then
                echo "<p class='ok'>✅ Verified primary CDB connection</p>" >> "$html_file"
            else
                echo "<p class='critical'>❌ Primary verification failed</p>" >> "$html_file"
                echo "<pre>Verification output: $verify_primary</pre>" >> "$html_file"
                primary_conn=""
            fi
            ;;
        *)
            echo "<p class='critical'>❌ Unsupported database role: $db_role</p>" >> "$html_file"
            return 1
            ;;
    esac

    echo "</div>" >> "$html_file"
    echo "$primary_conn"
}
SET MARKUP HTML ON
SET ECHO OFF FEEDBACK OFF
SET LINESIZE 120 PAGESIZE 100
COLUMN begin_hour FORMAT A20 HEADING "Hour"
COLUMN instance_number FORMAT 99 HEADING "Inst#"
COLUMN average_active_sessions FORMAT 9999.99 HEADING "AAS"
COLUMN status FORMAT A10 HEADING "Status"
SPOOL hourly_instance_aas.html

PROMPT <h2>Hourly Average Active Sessions per Instance (Last 24 Hours)</h2>

WITH interval_data AS (
  SELECT
    TRUNC(begin_time,'HH24') AS begin_hour,
    instance_number,
    MAX(CASE WHEN metric_name = 'Average Active Sessions' THEN average END) AS aas
  FROM dba_hist_con_sysmetric_summ
  WHERE begin_time >= SYSDATE - 1
    AND metric_name = 'Average Active Sessions'
  GROUP BY TRUNC(begin_time,'HH24'), instance_number
)
SELECT
  TO_CHAR(begin_hour, 'YYYY-MM-DD HH24:MI') AS begin_hour,
  instance_number,
  ROUND(aas, 2) AS average_active_sessions,
  CASE
    WHEN aas >= 10 THEN 'CRITICAL'
    WHEN aas >= 5 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM interval_data
ORDER BY begin_hour, instance_number;

SPOOL OFF;


SET LINESIZE 200
SET PAGESIZE 100
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A50
COLUMN wait_time_milli FORMAT 999
COLUMN wait_count FORMAT 999999

SELECT inst_id,
       event,
       wait_time_milli,
       wait_count
  FROM gv$event_histogram
 WHERE event IN (
       'gc buffer busy acquire',
       'gc buffer busy release',
       'gc cr block busy'
 )
   AND wait_count > 0
 ORDER BY inst_id, event, wait_time_milli;

SET LINESIZE 200
SET PAGESIZE 100
COLUMN inst_id FORMAT 99
COLUMN event FORMAT A50
COLUMN wait_count FORMAT 9999999

SELECT inst_id,
       event,
       COUNT(*) AS wait_count
  FROM gv$active_session_history
 WHERE sample_time > SYSDATE - 5/1440
   AND session_state = 'WAITING'
 GROUP BY inst_id, event
 ORDER BY inst_id, wait_count DESC;


SET LINESIZE 200
SET PAGESIZE 100
COLUMN snap_time FORMAT A20
COLUMN instance_number FORMAT 99
COLUMN iops FORMAT 999999.99

WITH io_stats AS (
  SELECT s.snap_id,
         s.instance_number,
         TO_CHAR(s.begin_interval_time, 'YYYY-MM-DD HH24:MI') AS snap_time,
         MAX(CASE WHEN ss.stat_name = 'physical read IO requests' THEN ss.value END) AS read_io,
         MAX(CASE WHEN ss.stat_name = 'physical write IO requests' THEN ss.value END) AS write_io,
         s.begin_interval_time,
         s.end_interval_time
    FROM dba_hist_sysstat ss
    JOIN dba_hist_snapshot s
      ON ss.snap_id = s.snap_id AND ss.instance_number = s.instance_number
   WHERE ss.stat_name IN ('physical read IO requests', 'physical write IO requests')
     AND s.begin_interval_time > SYSDATE - 1
   GROUP BY s.snap_id, s.instance_number, s.begin_interval_time, s.end_interval_time
),
deltas AS (
  SELECT snap_time,
         instance_number,
         (read_io + write_io) -
         LAG(read_io + write_io) OVER (PARTITION BY instance_number ORDER BY begin_interval_time) AS total_io,
         (CAST(end_interval_time AS DATE) - CAST(begin_interval_time AS DATE)) * 24 * 60 * 60 AS elapsed_seconds
    FROM io_stats
)
SELECT snap_time,
       instance_number,
       ROUND(total_io / NULLIF(elapsed_seconds, 0), 2) AS iops
  FROM deltas
 WHERE total_io IS NOT NULL
 ORDER BY snap_time DESC, instance_number;

-- 59_gc_contention_19c.sql - Identify global cache contention in RAC
SET ECHO OFF FEEDBACK OFF PAGES 50 LINES 167 TRIMSPOOL ON
SET MARKUP HTML ON
SPOOL 59_gc_contention_19c.html

PROMPT <h2>Global Cache Contention Events (RAC Only)</h2>

COLUMN event FORMAT A30
SELECT inst_id AS "Inst#", event AS "Event",
       total_waits AS "# Waits",
       ROUND(time_waited*10) AS "Time (ms)",
       ROUND((time_waited*10)/DECODE(total_waits, 0, 1, total_waits), 1) AS "Avg Wait (ms)"
FROM gv$system_event
WHERE event IN ('gc buffer busy acquire','gc buffer busy release','gc cr block busy')
ORDER BY inst_id, time_waited DESC;

SPOOL OFF;


-- 60_interconnect_19c.sql - Monitor RAC interconnect usage and latency
SET ECHO OFF FEEDBACK OFF PAGES 100 LINES 200 TRIMSPOOL ON
SET MARKUP HTML ON
SPOOL 60_interconnect_19c.html

PROMPT <h2>Interconnect Statistics (RAC Only)</h2>

-- Global Cache Block Transfers and Lost Blocks
PROMPT <h3>Global Cache Block Transfers &amp; Lost Blocks (cumulative)</h3>
COLUMN Lost FORMAT 9999999
COLUMN LostPct FORMAT 990.00
SELECT inst_id AS "Inst#", 
       MAX(CASE WHEN name='gc cr blocks received' THEN value END)    AS "CR_Rcvd",
       MAX(CASE WHEN name='gc current blocks received' THEN value END) AS "CUR_Rcvd",
       MAX(CASE WHEN name='gc cr blocks served' THEN value END)      AS "CR_Sent",
       MAX(CASE WHEN name='gc current blocks served' THEN value END) AS "CUR_Sent",
       MAX(CASE WHEN name='global cache blocks lost' THEN value END) AS "Lost",
       ROUND( 100 * MAX(CASE WHEN name='global cache blocks lost' THEN value END)
                / GREATEST( MAX(CASE WHEN name='gc cr blocks served' THEN value END)
                          + MAX(CASE WHEN name='gc current blocks served' THEN value END), 1)
             , 2) AS "LostPct"
FROM gv$sysstat
WHERE name IN (
    'gc cr blocks received','gc current blocks received',
    'gc cr blocks served','gc current blocks served',
    'global cache blocks lost'
)
GROUP BY inst_id
ORDER BY inst_id;

-- Global Cache Transfer Latency (Average receive times in ms)
PROMPT <h3>Global Cache Transfer Latency (Avg Receive Time per Inst)</h3>
COLUMN "Avg CR (ms)"  FORMAT 99990.00
COLUMN "Avg CUR (ms)" FORMAT 99990.00
SELECT inst_id AS "Inst#",
       ROUND( MAX(CASE WHEN name='gc cr block receive time' THEN value END)
            / GREATEST(MAX(CASE WHEN name='gc cr blocks received' THEN value END), 1) * 10, 2) 
            AS "Avg CR (ms)",
       ROUND( MAX(CASE WHEN name='gc current block receive time' THEN value END)
            / GREATEST(MAX(CASE WHEN name='gc current blocks received' THEN value END), 1) * 10, 2) 
            AS "Avg CUR (ms)"
FROM gv$sysstat
WHERE name IN (
    'gc cr block receive time','gc cr blocks received',
    'gc current block receive time','gc current blocks received'
)
GROUP BY inst_id
ORDER BY inst_id;

SPOOL OFF;



-- 61_iops_trend_19c.sql - 24-hour IOPS trend per instance (uses AWR data)
SET ECHO OFF FEEDBACK OFF PAGES 200 LINES 200 TRIMSPOOL ON
SET MARKUP HTML ON
SPOOL 61_iops_trend_19c.html

PROMPT <h2>IOPS Trend (Last 24 Hours per Instance)</h2>

COLUMN "Time" FORMAT A17
-- Note: PIVOT for up to 8 instances; extend if more instances in the RAC
SELECT TO_CHAR(begin_interval_time, 'DD-Mon HH24:MI') AS "Time",
       ROUND(NVL(inst1,0),2) AS "Inst1", ROUND(NVL(inst2,0),2) AS "Inst2",
       ROUND(NVL(inst3,0),2) AS "Inst3", ROUND(NVL(inst4,0),2) AS "Inst4",
       ROUND(NVL(inst5,0),2) AS "Inst5", ROUND(NVL(inst6,0),2) AS "Inst6",
       ROUND(NVL(inst7,0),2) AS "Inst7", ROUND(NVL(inst8,0),2) AS "Inst8"
FROM (
  SELECT s.begin_interval_time, t.instance_number,
         -- Sum average IO request rates (reads + writes + redo writes) for each instance snapshot
         SUM(CASE WHEN t.metric_name = 'Physical Read Total IO Requests Per Sec' THEN t.average ELSE 0 END
           + CASE WHEN t.metric_name = 'Physical Write Total IO Requests Per Sec' THEN t.average ELSE 0 END
           + CASE WHEN t.metric_name = 'Redo Writes Per Sec' THEN t.average ELSE 0 END) AS total_iops
  FROM dba_hist_sysmetric_summary t
  JOIN dba_hist_snapshot s 
    ON t.snap_id = s.snap_id AND t.dbid = s.dbid AND t.instance_number = s.instance_number
  WHERE t.metric_name IN (
    'Physical Read Total IO Requests Per Sec',
    'Physical Write Total IO Requests Per Sec',
    'Redo Writes Per Sec'
  )
    AND s.begin_interval_time >= SYSDATE - 1
  GROUP BY s.begin_interval_time, t.instance_number
) pivot_data
PIVOT (
  MAX(total_iops) FOR instance_number IN (
    1 AS inst1, 2 AS inst2, 3 AS inst3, 4 AS inst4,
    5 AS inst5, 6 AS inst6, 7 AS inst7, 8 AS inst8
  )
)
ORDER BY "Time";

SPOOL OFF;

-- 61_iops_trend_19c.sql - 24-hour IOPS trend per instance (uses AWR data)
SET ECHO OFF FEEDBACK OFF PAGES 200 LINES 200 TRIMSPOOL ON
SET MARKUP HTML ON
SPOOL 61_iops_trend_19c.html

PROMPT <h2>IOPS Trend (Last 24 Hours per Instance)</h2>

COLUMN "Time" FORMAT A17
-- Note: PIVOT for up to 8 instances; extend if more instances in the RAC
SELECT TO_CHAR(begin_interval_time, 'DD-Mon HH24:MI') AS "Time",
       ROUND(NVL(inst1,0),2) AS "Inst1", ROUND(NVL(inst2,0),2) AS "Inst2",
       ROUND(NVL(inst3,0),2) AS "Inst3", ROUND(NVL(inst4,0),2) AS "Inst4",
       ROUND(NVL(inst5,0),2) AS "Inst5", ROUND(NVL(inst6,0),2) AS "Inst6",
       ROUND(NVL(inst7,0),2) AS "Inst7", ROUND(NVL(inst8,0),2) AS "Inst8"
FROM (
  SELECT s.begin_interval_time, t.instance_number,
         -- Sum average IO request rates (reads + writes + redo writes) for each instance snapshot
         SUM(CASE WHEN t.metric_name = 'Physical Read Total IO Requests Per Sec' THEN t.average ELSE 0 END
           + CASE WHEN t.metric_name = 'Physical Write Total IO Requests Per Sec' THEN t.average ELSE 0 END
           + CASE WHEN t.metric_name = 'Redo Writes Per Sec' THEN t.average ELSE 0 END) AS total_iops
  FROM dba_hist_sysmetric_summary t
  JOIN dba_hist_snapshot s 
    ON t.snap_id = s.snap_id AND t.dbid = s.dbid AND t.instance_number = s.instance_number
  WHERE t.metric_name IN (
    'Physical Read Total IO Requests Per Sec',
    'Physical Write Total IO Requests Per Sec',
    'Redo Writes Per Sec'
  )
    AND s.begin_interval_time >= SYSDATE - 1
  GROUP BY s.begin_interval_time, t.instance_number
) pivot_data
PIVOT (
  MAX(total_iops) FOR instance_number IN (
    1 AS inst1, 2 AS inst2, 3 AS inst3, 4 AS inst4,
    5 AS inst5, 6 AS inst6, 7 AS inst7, 8 AS inst8
  )
)
ORDER BY "Time";

-- 62_top_waits_19c.sql - Show top 5 wait events per RAC instance (excluding idle waits)
SET ECHO OFF FEEDBACK OFF PAGES 100 LINES 180 TRIMSPOOL ON
SET MARKUP HTML ON
SPOOL 62_top_waits_19c.html

PROMPT <h2>Top 5 Wait Events per Instance</h2>

COLUMN "Wait Event" FORMAT A40
SELECT inst_id AS "Inst#",
       event AS "Wait Event",
       ROUND(time_waited/100, 2) AS "Time (s)",
       total_waits AS "# Waits",
       ROUND((time_waited*10)/DECODE(total_waits, 0, 1, total_waits), 2) AS "Avg Wait (ms)"
FROM (
  SELECT e.inst_id, e.event, e.time_waited, e.total_waits,
         RANK() OVER (PARTITION BY e.inst_id ORDER BY e.time_waited DESC) AS rk
  FROM gv$system_event e
  WHERE e.event NOT IN (
    SELECT name FROM v$event_name WHERE wait_class = 'Idle'
  )
)
WHERE rk <= 5
ORDER BY inst_id, "Time (s)" DESC;

SPOOL OFF;



PROMPT <h2>Top 10 Full Table Scan SQLs (Non-SYS) with High Logical Reads</h2>

SELECT *
FROM (
  SELECT
    sql_id,
    username,
    ROUND(buffer_gets / DECODE(executions, 0, 1, executions)) AS avg_buffer_gets,
    executions,
    buffer_gets,
    CASE
      WHEN ROUND(buffer_gets / DECODE(executions, 0, 1, executions)) > 100000 THEN 'CRITICAL'
      WHEN ROUND(buffer_gets / DECODE(executions, 0, 1, executions)) > 50000 THEN 'WARNING'
      ELSE 'OK'
    END AS status,
    sql_text
  FROM (
    SELECT
      ss.sql_id,
      st.sql_text,
      ss.executions,
      ss.buffer_gets,
      u.username
    FROM dba_hist_sqlstat ss
    JOIN dba_hist_sqltext st ON ss.sql_id = st.sql_id
    JOIN dba_users u ON ss.parsing_schema_id = u.user_id
    WHERE ss.snap_id > (
      SELECT MAX(snap_id) - 48 FROM dba_hist_snapshot
    )
      AND u.username NOT IN ('SYS', 'SYSTEM')
      AND EXISTS (
        SELECT 1
        FROM dba_hist_sql_plan p
        WHERE p.sql_id = ss.sql_id
          AND p.operation = 'TABLE ACCESS'
          AND p.options = 'FULL'
      )
  )
  ORDER BY buffer_gets DESC
)
WHERE ROWNUM <= 10;

SPOOL OFF;


PROMPT <h2>Peak DB Time per Instance in the Last 24 Hours</h2>

WITH recent_snaps AS (
  SELECT snap_id, dbid, instance_number, begin_interval_time, end_interval_time
  FROM dba_hist_snapshot
  WHERE begin_interval_time >= SYSDATE - 1
),
db_time_data AS (
  SELECT
    s.instance_number AS inst_id,
    s.snap_id,
    s.begin_interval_time,
    s.end_interval_time,
    ROUND((t.value / 1000000), 2) AS db_time_sec
  FROM recent_snaps s
  JOIN dba_hist_sys_time_model t
    ON s.snap_id = t.snap_id
   AND s.dbid = t.dbid
   AND s.instance_number = t.instance_number
  WHERE t.stat_name = 'DB time'
)
SELECT *
FROM (
  SELECT
    inst_id,
    snap_id,
    begin_interval_time,
    end_interval_time,
    db_time_sec,
    CASE
      WHEN db_time_sec > 3600 THEN 'CRITICAL'
      WHEN db_time_sec > 1800 THEN 'WARNING'
      ELSE 'OK'
    END AS status
  FROM db_time_data
  ORDER BY db_time_sec DESC
)
WHERE ROWNUM <= 10;

SPOOL OFF;

SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL db_time_peak.html

PROMPT <h2>Top 30 DB Time Intervals per Instance in the Last 24 Hours</h2>

WITH db_time_deltas AS (
  SELECT
    s.instance_number AS inst_id,
    s.snap_id,
    s.begin_interval_time,
    s.end_interval_time,
    t.value,
    LAG(t.value) OVER (PARTITION BY s.instance_number ORDER BY s.snap_id) AS prev_value
  FROM
    dba_hist_snapshot s
    JOIN dba_hist_sys_time_model t
      ON s.snap_id = t.snap_id
     AND s.dbid = t.dbid
     AND s.instance_number = t.instance_number
  WHERE
    s.begin_interval_time >= SYSDATE - 1
    AND t.stat_name = 'DB time'
),
db_time_calc AS (
  SELECT
    inst_id,
    snap_id,
    begin_interval_time,
    end_interval_time,
    ROUND(NVL(value - prev_value, 0) / 1e6 / 60, 2) AS db_time_min
  FROM
    db_time_deltas
)
SELECT *
FROM (
  SELECT
    inst_id,
    snap_id,
    begin_interval_time,
    end_interval_time,
    db_time_min,
    CASE
      WHEN db_time_min > 60 THEN 'CRITICAL'
      WHEN db_time_min > 30 THEN 'WARNING'
      ELSE 'OK'
    END AS status
  FROM
    db_time_calc
  ORDER BY
    db_time_min DESC
)
WHERE ROWNUM <= 30;

SPOOL OFF;

##
SELECT
    inst_id,
    ROUND(COUNT(*) / (24 * 60 * 60), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time >= SYSDATE - 1
GROUP BY
    inst_id
ORDER BY
    inst_id;

##
SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL open_cursor_stats.html

PROMPT <h2>Open Cursor Statistics per RAC Instance</h2>

SELECT
    inst_id,
    TO_CHAR(execute_count, '999G999G999G999') AS "SQL Execution",
    TO_CHAR(parse_count, '999G999G999G999') AS "Parse Count",
    TO_CHAR(cursor_hits, '999G999G999G999') AS "Cursor Hits",
    ROUND((parse_count / NULLIF(execute_count, 0)) * 100, 2) AS "Parse % Total",
    ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) AS "Cursor Cache % Total",
    CASE
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 90 THEN 'OK'
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 80 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS status
FROM (
    SELECT
        inst_id,
        MAX(CASE WHEN name = 'execute count' THEN value END) AS execute_count,
        MAX(CASE WHEN name = 'parse count (total)' THEN value END) AS parse_count,
        MAX(CASE WHEN name = 'session cursor cache hits' THEN value END) AS cursor_hits
    FROM
        gv$sysstat
    WHERE
        name IN ('execute count', 'parse count (total)', 'session cursor cache hits')
    GROUP BY
        inst_id
)
ORDER BY
    inst_id;

SPOOL OFF;

====
SELECT
    inst_id,
    ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                      EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                      EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                      EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
         ), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time BETWEEN TO_DATE('2025-06-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
                    AND TO_DATE('2025-06-01 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
GROUP BY
    inst_id
ORDER BY
    inst_id;

SET ECHO OFF FEEDBACK OFF
SET LINESIZE 200 PAGESIZE 100
COLUMN INST_ID                FORMAT 99
COLUMN HOST_ID                FORMAT A30
COLUMN CONTAINER_NAME         FORMAT A30
COLUMN PROBLEM_KEY            FORMAT A30
COLUMN ORIGINATING_TIMESTAMP  FORMAT A45
COLUMN RPT                    FORMAT 9999
COLUMN STATUS                 FORMAT A10
SPOOL ora_errors_rac_last24h.html

PROMPT <h2>ORA‑ Errors (Last 24h, All RAC Instances)</h2>

SELECT
  INST_ID,
  TO_CHAR(TRUNC(ORIGINATING_TIMESTAMP,'MI'),'DD.MM.YYYY HH24:MI') AS ORIGINATING_TIMESTAMP,
  HOST_ID,
  CONTAINER_NAME,
  NVL(PROBLEM_KEY, 'N/A') AS PROBLEM_KEY,
  COUNT(*) AS RPT,
  CASE
    WHEN COUNT(*) > 20 THEN 'CRITICAL'
    WHEN COUNT(*) > 5 THEN 'WARNING'
    ELSE 'OK'
  END AS STATUS,
  SUBSTR(MESSAGE_TEXT,1,200) AS MESSAGE_TEXT
FROM TABLE(
  gv$(
    CURSOR(
      SELECT
        INST_ID,
        ORIGINATING_TIMESTAMP,
        HOST_ID,
        CONTAINER_NAME,
        PROBLEM_KEY,
        MESSAGE_TEXT
      FROM v$diag_alert_ext
      WHERE ORIGINATING_TIMESTAMP >= SYSDATE - 1
        AND COMPONENT_ID = 'rdbms'
        AND MESSAGE_TEXT LIKE '%ORA-%'
    )
  )
)
GROUP BY
  INST_ID,
  HOST_ID,
  CONTAINER_NAME,
  NVL(PROBLEM_KEY, 'N/A'),
  TRUNC(ORIGINATING_TIMESTAMP, 'MI'),
  SUBSTR(MESSAGE_TEXT,1,200)
ORDER BY INST_ID, RPT DESC, ORIGINATING_TIMESTAMP DESC;

SPOOL OFF;


alter session set cursor_sharing=exact;

col username for a40
col sql_text for a70
col sid for 9999999
col status for a10
col slv_req for 9999999
col slv_alloc for 9999999
col secs_in_q for 99999999
col IS_ADAPTIVE_PLAN for a30

SELECT inst_id,
       sid,
       session_serial# sess#,
       username,
       sql_id,
       status,
       px_servers_requested slv_req,
       px_servers_allocated slv_alloc,
       substr(sql_text,1,30)||'...' sql_text,
       LAST_REFRESH_TIME,
       IS_ADAPTIVE_PLAN,
       PX_MAXDOP,
       queuing_time/1000000 secs_in_q,
       RM_CONSUMER_GROUP
FROM gv\$sql_monitor
WHERE status in ('QUEUED', 'EXECUTING')
  AND sql_text is not null
  AND px_servers_requested is not null
  AND px_servers_allocated is not null
  AND px_servers_requested != px_servers_allocated
ORDER BY status desc, secs_in_q desc, sql_id;


col HOST_ID for a30
col CONTAINER_NAME for a30
col PROBLEM_KEY for a30
col ORIGINATING_TIMESTAMP for a45

col rpt for a10

select 
    originating_timestamp,
    HOST_ID,
    NVL(PROBLEM_KEY, 0),
    count(*) as REPEATED,
    CONTAINER_NAME,
    substr(MESSAGE_TEXT, 1, 70) MESSAGE,
    CASE
        WHEN MESSAGE_TYPE = 1 THEN 'UNK'
        WHEN MESSAGE_TYPE = 2 THEN 'INCIDENT_ERROR'
        WHEN MESSAGE_TYPE = 3 THEN 'ERROR'
        WHEN MESSAGE_TYPE = 4 THEN 'WARNING'
        WHEN MESSAGE_TYPE = 5 THEN 'NOTIFICATION'
        WHEN MESSAGE_TYPE = 6 THEN 'TRACE'
    END AS MESSAGE_TYPE_DESC,
    CASE
        WHEN MESSAGE_LEVEL = 1 THEN 'CRITICAL'
        WHEN MESSAGE_LEVEL = 2 THEN 'SEVERE'
        WHEN MESSAGE_LEVEL = 8 THEN 'IMPORTANT'
        WHEN MESSAGE_LEVEL = 16 THEN 'NORMAL'
    END AS MESSAGE_LEVEL_DESC,
    x.*
FROM TABLE (gv$ (CURSOR (SELECT * FROM V$DIAG_ALERT_EXT))) x
WHERE originating_timestamp > (SYSDATE - 12/24)
  AND substr(MESSAGE_TEXT, 1, 20) like '%ORA-%'
  AND substr(MESSAGE_TEXT, 1, 20) not like '%Result%'
GROUP BY originating_timestamp, HOST_ID, PROBLEM_KEY, CONTAINER_NAME, MESSAGE_TEXT
ORDER BY 3 DESC;

##

alter session set cursor_sharing=exact;

COL px_qcsid HEAD QC_SID FOR A13
COL px_instances FOR A100
COL px_username HEAD USERNAME FOR A25 WRAP

SELECT
  pxs.qcsid || ',' || pxs.qcserial# px_qcsid,
  pxs.qcinst_id,
  ses.username px_username,
  ses.sql_id,
  pxs.degree,
  pxs.req_degree,
  COUNT(*) slaves,
  COUNT(DISTINCT pxs.inst_id) inst_cnt,
  MIN(pxs.inst_id) min_inst,
  MAX(pxs.inst_id) max_inst,
  -- LISTAGG(TO_CHAR(pxs.inst_id), ',') WITHIN GROUP (ORDER BY pxs.inst_id) px_instances
FROM
  gv\$px_session pxs,
  gv\$session ses,
  gv\$px_process p
WHERE
  ses.sid = pxs.sid
  AND ses.serial# = pxs.serial#
  AND p.sid = pxs.sid
  AND pxs.inst_id = ses.inst_id
  AND ses.inst_id = p.inst_id
  AND pxs.req_degree IS NOT NULL -- qc
GROUP BY
  pxs.qcsid || ',' || pxs.qcserial#,
  pxs.qcinst_id,
  ses.username,
  ses.sql_id,
  pxs.degree,
  pxs.req_degree
ORDER BY
  pxs.qcinst_id,
  slaves DESC;

###
ol ERROR_NUMBER for a30
col USERNAME for a30
col SERVICE_NAME for a30
col program for a50

select ERROR_NUMBER, count(*) as repeated, inst_id, sid, SESSION_SERIAL#, username, sql_id, program, service_name, FIRST_REFRESH_TIME
from GV\$SQL_MONITOR
where ERROR_NUMBER is not null 
  and FIRST_REFRESH_TIME > sysdate - 1/24
group by ERROR_NUMBER, inst_id, sid, SESSION_SERIAL#, username, sql_id, program, service_name, FIRST_REFRESH_TIME
order by FIRST_REFRESH_TIME;

select *
from (
  select b.inst_id, b.sid, b.serial#, a.spid, substr(b.machine,1,30) machine,
    to_char(b.logon_time,'dd-mon-yyyy hh24:mi:ss') logon_time,
    substr(b.username,1,30) username,
    substr(b.osuser,1,20) os_user,
    substr(b.program,1,30) program,
    substr(b.event,1,20) event,
    b.wait_class,
    b.last_call_et AS last_call_et_secs,
    b.sql_id
  from gv\$session b, gv\$process a
  where b.paddr = a.addr
    and a.inst_id = b.inst_id
    and b.type='USER'
    and b.status='ACTIVE'
    and b.last_call_et > 3600
  order by b.logon_time, b.last_call_et
)
where rownum < 10;
                  
col event for a30
col username for a30
col WAIT_CLASS for a30

select inst_id, blocking_session, sid, serial#, username, wait_class, EVENT, seconds_in_wait, sql_id
from gv\$session
where blocking_session is not NULL and seconds_in_wait > 300
order by seconds_in_wait;

select i.host_name, i.instance_name, i.version_full version, i.instance_number, p.name pdb, 
       p.open_mode, p.restricted, i.STARTUP_TIME,
       round((i.startup_time - (sysdate - 1/24)), 2) as "Bit"
from gv\$instance i, gv\$pdbs p
where i.inst_id = p.inst_id
order by 2;

 Col NAME for a40;
Col N1 for a1
Col N2 for a1
Col N3 for a1
Col N4 for a1
Col N5 for a1
Col N6 for a1
Col N7 for a1
Col N8 for a1

SELECT 
    a.NAME,
    b.node1 as N1,
    b.node2 as N2,
    b.node3 as N3,
    b.node4 as N4,
    b.node5 as N5,
    b.node6 as N6,
    b.node7 as N7,
    b.node8 as N8 
FROM 
    (SELECT DISTINCT UPPER(NAME) NAME FROM gv\$services WHERE NAME NOT LIKE 'SYS$%') a,
    (SELECT 
        UPPER(NAME) NAME,
        MAX(DECODE(inst_id, 1, 'Y', '')) node1,
        MAX(DECODE(inst_id, 2, 'Y', '')) node2,
        MAX(DECODE(inst_id, 3, 'Y', '')) node3,
        MAX(DECODE(inst_id, 4, 'Y', '')) node4,
        MAX(DECODE(inst_id, 5, 'Y', '')) node5,
        MAX(DECODE(inst_id, 6, 'Y', '')) node6,
        MAX(DECODE(inst_id, 7, 'Y', '')) node7,
        MAX(DECODE(inst_id, 8, 'Y', '')) node8
    FROM gv\$active_services
    WHERE NAME NOT LIKE 'SYS$%'
    GROUP BY UPPER(NAME)
    ) b
WHERE a.NAME = b.NAME(+)
ORDER BY 1;

  
col event for a30
col username for a30
col WAIT_CLASS for a30
col blocking_status for a100
col Machine for a40
col LOCKED_OBJECT for a40

SELECT decode(request, 0, 'Holder: ', 'Waiter: ') || l.sid sess, machine,
       do.object_name AS locked_object, id1, id2, lmode, request, l.type
FROM gv\$lock l
JOIN gv\$session s ON l.sid = s.sid AND l.inst_id = s.inst_id
JOIN gv\$locked_object lo ON l.sid = lo.session_id AND l.inst_id = lo.inst_id
JOIN dba_objects do ON lo.object_id = do.object_id
WHERE (id1, id2, l.type) IN (
  SELECT id1, id2, type FROM gv\$lock WHERE request > 0
)
ORDER BY id1, request;

                  
                  
SET MARKUP HTML ON
SET ECHO OFF FEEDBACK OFF
SET LINESIZE 200 PAGESIZE 100
COLUMN inst_id                 FORMAT 99
COLUMN HOST_ID                FORMAT A30
COLUMN CONTAINER_NAME         FORMAT A30
COLUMN PROBLEM_KEY            FORMAT A30
COLUMN ORIGINATING_TIMESTAMP  FORMAT A45
COLUMN RPT                    FORMAT 9999
COLUMN STATUS                 FORMAT A10
SPOOL ora_errors_rac_last24h.html

PROMPT <h2>ORA‑ Errors (Last 24h, All RAC Instances)</h2>

SELECT inst_id,
       TO_CHAR(originating_timestamp, 'DD.MM.YYYY HH24:MI') AS ORIGINATING_TIMESTAMP,
       host_id,
       container_name,
       NVL(problem_key, 'N/A') AS problem_key,
       COUNT(*) AS RPT,
       CASE
         WHEN COUNT(*) > 10 THEN 'CRITICAL'
         WHEN COUNT(*) > 3 THEN 'WARNING'
         ELSE 'OK'
       END AS STATUS,
       SUBSTR(message_text,1,200) AS MESSAGE_TEXT
FROM TABLE(
       gv$(
         CURSOR(
           SELECT inst_id,
                  originating_timestamp,
                  host_id,
                  container_name,
                  problem_key,
                  message_text
             FROM v$diag_alert_ext
            WHERE originating_timestamp >= SYSDATE - 1
              AND component_id = 'rdbms'
              AND message_text LIKE '%ORA-%'
         )
       )
     )
GROUP BY inst_id,
         host_id,
         container_name,
         COALESCE(problem_key,'N/A'),
         TRUNC(originating_timestamp,'MI'),
         SUBSTR(message_text,1,200)
ORDER BY inst_id, RPT DESC, ORIGINATING_TIMESTAMP DESC;

SPOOL OFF;


SELECT
    inst_id,
    ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                      EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                      EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                      EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
         ), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time BETWEEN TO_DATE('2025-06-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
                    AND TO_DATE('2025-06-01 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
GROUP BY
    inst_id
ORDER BY
    inst_id;
 
SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL rac_alert_errors.html

PROMPT <h2>ORA- Errors from All RAC Instances (Last 24 Hours)</h2>

SELECT
    inst_id,
    TO_CHAR(originating_timestamp, 'DD.MM.YYYY HH24:MI:SS') AS message_time,
    host_id,
    adr_home,
    message_text
FROM
    TABLE(gv$(CURSOR(
        SELECT
            originating_timestamp,
            host_id,
            adr_home,
            message_text
        FROM
            v$diag_alert_ext
        WHERE
            originating_timestamp > SYSDATE - 1
            AND component_id = 'rdbms'
            AND message_text LIKE '%ORA-%'
    )))
ORDER BY
    originating_timestamp DESC;

SPOOL OFF;

SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL open_cursor_stats.html

PROMPT <h2>Open Cursor Statistics per RAC Instance</h2>

SELECT
    inst_id,
    TO_CHAR(execute_count, '999G999G999G999') AS "SQL Execution",
    TO_CHAR(parse_count, '999G999G999G999') AS "Parse Count",
    TO_CHAR(cursor_hits, '999G999G999G999') AS "Cursor Hits",
    ROUND((parse_count / NULLIF(execute_count, 0)) * 100, 2) AS "Parse % Total",
    ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) AS "Cursor Cache % Total",
    CASE
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 90 THEN 'OK'
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 80 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS status
FROM (
    SELECT
        inst_id,
        MAX(CASE WHEN name = 'execute count' THEN value END) AS execute_count,
        MAX(CASE WHEN name = 'parse count (total)' THEN value END) AS parse_count,
        MAX(CASE WHEN name = 'session cursor cache hits' THEN value END) AS cursor_hits
    FROM
        gv$sysstat
    WHERE
        name IN ('execute count', 'parse count (total)', 'session cursor cache hits')
    GROUP BY
        inst_id
)
ORDER BY
    inst_id;

SPOOL OFF;

SELECT
    inst_id,
    ROUND(COUNT(*) / (24 * 60 * 60), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time >= SYSDATE - 1
GROUP BY
    inst_id
ORDER BY
    inst_id;

SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL db_time_peak.html

PROMPT <h2>Top 30 DB Time Intervals per Instance in the Last 24 Hours</h2>

WITH db_time_deltas AS (
  SELECT
    s.instance_number AS inst_id,
    s.snap_id,
    s.begin_interval_time,
    s.end_interval_time,
    t.value,
    LAG(t.value) OVER (PARTITION BY s.instance_number ORDER BY s.snap_id) AS prev_value
  FROM
    dba_hist_snapshot s
    JOIN dba_hist_sys_time_model t
      ON s.snap_id = t.snap_id
     AND s.dbid = t.dbid
     AND s.instance_number = t.instance_number
  WHERE
    s.begin_interval_time >= SYSDATE - 1
    AND t.stat_name = 'DB time'
),
db_time_calc AS (
  SELECT
    inst_id,
    snap_id,
    begin_interval_time,
    end_interval_time,
    ROUND(NVL(value - prev_value, 0) / 1e6 / 60, 2) AS db_time_min
  FROM
    db_time_deltas
)
SELECT *
FROM (
  SELECT
    inst_id,
    snap_id,
    begin_interval_time,
    end_interval_time,
    db_time_min,
    CASE
      WHEN db_time_min > 60 THEN 'CRITICAL'
      WHEN db_time_min > 30 THEN 'WARNING'
      ELSE 'OK'
    END AS status
  FROM
    db_time_calc
  ORDER BY
    db_time_min DESC
)
WHERE ROWNUM <= 30;

SPOOL OFF;


SELECT
    inst_id,
    metric_name,
    ROUND(value, 2) AS metric_value,
    metric_unit,
    CASE metric_name
        WHEN 'Average Active Sessions' THEN
            CASE
                WHEN value > 10 THEN 'CRITICAL'
                WHEN value > 5 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Average Synchronous Single-Block Read Latency' THEN
            CASE
                WHEN value > 20 THEN 'CRITICAL'
                WHEN value > 10 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'CPU Usage Per Sec' THEN
            CASE
                WHEN value > 90 THEN 'CRITICAL'
                WHEN value > 70 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Background CPU Usage Per Sec' THEN
            CASE
                WHEN value > 50 THEN 'CRITICAL'
                WHEN value > 30 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'DB Block Changes Per Txn' THEN
            CASE
                WHEN value > 100 THEN 'CRITICAL'
                WHEN value > 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Executions Per Sec' THEN
            CASE
                WHEN value < 10 THEN 'CRITICAL'
                WHEN value < 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Host CPU Usage Per Sec' THEN
            CASE
                WHEN value > 90 THEN 'CRITICAL'
                WHEN value > 70 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'I/O Megabytes per Second' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'I/O Requests per Second' THEN
            CASE
                WHEN value > 10000 THEN 'CRITICAL'
                WHEN value > 5000 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Logical Reads Per Txn' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Logons Per Sec' THEN
            CASE
                WHEN value > 100 THEN 'CRITICAL'
                WHEN value > 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Network Traffic Volume Per Sec' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Physical Reads Per Sec' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Physical Reads Per Txn' THEN
            CASE
                WHEN value > 100 THEN 'CRITICAL'
                WHEN value > 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Physical Writes Per Sec' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Redo Generated Per Sec' THEN
            CASE
                WHEN value > 500 THEN 'CRITICAL'
                WHEN value > 250 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Redo Generated Per Txn' THEN
            CASE
                WHEN value > 100 THEN 'CRITICAL'
                WHEN value > 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Response Time Per Txn' THEN
            CASE
                WHEN value > 1 THEN 'CRITICAL'
                WHEN value > 0.5 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'SQL Service Response Time' THEN
            CASE
                WHEN value > 1 THEN 'CRITICAL'
                WHEN value > 0.5 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'Total Parse Count Per Txn' THEN
            CASE
                WHEN value > 100 THEN 'CRITICAL'
                WHEN value > 50 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'User Calls Per Sec' THEN
            CASE
                WHEN value > 1000 THEN 'CRITICAL'
                WHEN value > 500 THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN 'User Transaction Per Sec' THEN
            CASE
                WHEN value < 10 THEN 'CRITICAL'
                WHEN value < 50 THEN 'WARNING'
                ELSE 'OK'
            END
        ELSE 'N/A'
    END AS status
FROM
    gv$sysmetric
WHERE
    metric_name IN (
        'Average Active Sessions',
        'Average Synchronous Single-Block Read Latency',
        'CPU Usage Per Sec',
        'Background CPU Usage Per Sec',
        'DB Block Changes Per Txn',
        'Executions Per Sec',
        'Host CPU Usage Per Sec',
        'I/O Megabytes per Second',
        'I/O Requests per Second',
        'Logical Reads Per Txn',
        'Logons Per Sec',
        'Network Traffic Volume Per Sec',
        'Physical Reads Per Sec',
        'Physical Reads Per Txn',
        'Physical Writes Per Sec',
        'Redo Generated Per Sec',
        'Redo Generated Per Txn',
        'Response Time Per Txn',
        'SQL Service Response Time',
        'Total Parse Count Per Txn',
        'User Calls Per Sec',
        'User Transaction Per Sec'
    )
    AND group_id = 2 -- Last 60-second interval
ORDER BY
    inst_id, metric_name;


set termout off
set linesize 90
set pagesize 20
ttitle center 'PDHC -  A Quick Health Check' skip 2
btitle center '<span style="background-color:#c90421;color:#ffffff;border:1px solid black;">Confidential</span>'
set markup html on spool on entmap off

spool DB_Detail_status.html
COLUMN current_instance NEW_VALUE current_instance NOPRINT;
SELECT rpad(instance_name, 17) current_instance FROM v$instance;
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
set linesize 400 pagesize 400
SET TERMOUT ON;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Average Number of active sessions                           |
PROMPT | This is not RAC aware script                                           |
PROMPT | Description: This number gives you an idea about the database workload |
PROMPT | or business. Higer this number, more is the database busy doing work on|
PROMPT | specific node                                                          |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select round((count(ash.sample_id) / ((CAST(end_time.sample_time AS DATE) - CAST(start_time.sample_time AS DATE))*24*60*60)),2) as AAS
from
        (select min(sample_time) sample_time
        from  v$active_session_history ash
        ) start_time,
        (select max(sample_time) sample_time
        from  v$active_session_history
        ) end_time,
        v$active_session_history ash
where ash.sample_time between start_time.sample_time and end_time.sample_time
group by end_time.sample_time,start_time.sample_time;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Load Profile of any database                                |
PROMPT | This is not RAC aware script                                           |
PROMPT | Description: This section contains same stats what you will see anytime|
PROMPT | in AWR of database. Few of the imp sections are                        |
PROMPT | DB Block Changes Per Txn, Average Active Sessions, Executions Per Sec  |
PROMPT | User Calls Per Sec, Physical Writes Per Sec, Physical Reads Per Txn etc|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

SELECT
    metric_name, inst_id
  , ROUND(value,2) w_metric_value
  , metric_unit
FROM
    gv$sysmetric
WHERE
    metric_name IN (
                                'Average Active Sessions'
                        , 'Average Synchronous Single-Block Read Latency'
                        , 'CPU Usage Per Sec'
                        , 'Background CPU Usage Per Sec'
                        , 'DB Block Changes Per Txn'
                        , 'Executions Per Sec'
                        , 'Host CPU Usage Per Sec'
                        , 'I/O Megabytes per Second'
                        , 'I/O Requests per Second'
                        , 'Logical Reads Per Txn'
                        , 'Logons Per Sec'
                        , 'Network Traffic Volume Per Sec'
                        , 'Physical Reads Per Sec'
                        , 'Physical Reads Per Txn'
                        , 'Physical Writes Per Sec'
                        , 'Redo Generated Per Sec'
                        , 'Redo Generated Per Txn'
                        , 'Response Time Per Txn'
                        , 'SQL Service Response Time'
                        , 'Total Parse Count Per Txn'
                        , 'User Calls Per Sec'
                        , 'User Transaction Per Sec'
)
AND group_id = 2 -- get last 60 sec metrics
ORDER BY
    metric_name, inst_id
/


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Sesions Waiting                                             |
PROMPT | Desc: The entries that are shown at the top are the sessions that have |
PROMPT | waited the longest amount of time that are waiting for non-idle wait   |
PROMPT | events (event column).
PROMPT | This is RAC aware script                                               |
PROMPT +------------------------------------------------------------------------+


set numwidth 15
set heading on
column state format a7 tru
column event format a25 tru
column last_sql format a40 tru
select sw.inst_id, sa.sql_id,sw.sid, sw.state, sw.event, sw.seconds_in_wait seconds,
sw.p1, sw.p2, sw.p3, sa.sql_text last_sql
from gv$session_wait sw, gv$session s, gv$sqlarea sa
where sw.event not in
('rdbms ipc message','smon timer','pmon timer',
'SQL*Net message from client','lock manager wait for remote message',
'ges remote message', 'gcs remote message', 'gcs for action', 'client message',
'pipe get', 'null event', 'PX Idle Wait', 'single-task message',
'PX Deq: Execution Msg', 'KXFQ: kxfqdeq - normal deqeue',
'listen endpoint status','slave wait','wakeup time manager')
and sw.seconds_in_wait > 0
and (sw.inst_id = s.inst_id and sw.sid = s.sid)
and (s.inst_id = sa.inst_id and s.sql_address = sa.address)
order by seconds desc;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 5 SQL statements in the past one hour                   |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on time waited in DB        |
PROMPT | This is sorted on the basis of the time each one of them spend in DB   |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select * from (
select active_session_history.sql_id,
 dba_users.username,
 sqlarea.sql_text,
sum(active_session_history.wait_time +
active_session_history.time_waited) ttl_wait_time
from gv$active_session_history active_session_history,
gv$sqlarea sqlarea,
 dba_users
where
active_session_history.sample_time between sysdate -  1/24  and sysdate
  and active_session_history.sql_id = sqlarea.sql_id
and active_session_history.user_id = dba_users.user_id
 group by active_session_history.sql_id,sqlarea.sql_text, dba_users.username
 order by 4 desc )
where rownum < 6;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top10 SQL statements present in cache (elapsed time)        |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on elapsed time spend in DB |
PROMPT | Look out for ways to reduce elapsed time, check if its waiting on some-|
PROMPT | thing or other issues behind the high run time of query.
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select rownum as rank, a.*
from (
select elapsed_Time/1000000 elapsed_time,
executions, inst_id,
elapsed_Time / (1000000 * decode(executions,0,1, executions) ) etime_per_exec,
buffer_gets,
disk_reads,
cpu_time
hash_value, sql_id,
sql_text
from  gv$sqlarea
where elapsed_time/1000000 > 5
order by etime_per_exec desc) a
where rownum < 11
/




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 5  SQL statements present in cache (PIOs or Disk Reads) |
PROMPT | This output is sorted on the basis of TOTAL DISK READS                 |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on Physical Reads or D-Reads|
PROMPT | Most probably queries coming under this section are suffering from Full|
PROMPT | Table Scans (FTS) or DB File Scattered Read (User IO) Waits. Look for  |
PROMPT | options if Index can help. Run SQL Tuning Advisories or do manual check|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select rownum as rank, a.*
from (
select disk_reads, inst_id,
executions,
disk_reads / decode(executions,0,1, executions) reads_per_exec,
hash_value,
sql_text
from  gv$sqlarea
where disk_reads > 10000
order by disk_reads desc) a
where rownum < 11
/


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 5  SQL statements present in cache (PIOs or Disk Reads) |
PROMPT | This output is sorted on the basis of DISK READS PER EXEC              |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on Physical Reads or D-Reads|
PROMPT | Most probably queries coming under this section are suffering from Full|
PROMPT | Table Scans (FTS) or DB File Scattered Read (User IO) Waits. Look for  |
PROMPT | options if Index can help. Run SQL Tuning Advisories or do manual check|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select rownum as rank, a.*
from (
select disk_reads, inst_id,
executions,
disk_reads / decode(executions,0,1, executions) reads_per_exec,
hash_value,
sql_text
from  gv$sqlarea
where disk_reads > 10000
order by reads_per_exec desc) a
where rownum < 11
/


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 10 SQL statements present in cache (LIOs or BufferReads)|
PROMPT | Sorted on the basis of TOTAL BUFFER GETS                               |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on Memmory Reads or L-Reads |
PROMPT | Most probably queries coming under this section are the ones doing FTS |
PROMPT | and might be waiting for any latch/Mutex to gain access on block. Pleas|
PROMPT | check the value of column 'gets_per_exec' that means average memory    |
PROMPT | reads per execution.                                                   |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+


select rownum as rank, a.*
from (
select buffer_gets,  inst_id,
executions,
buffer_gets/ decode(executions,0,1, executions) gets_per_exec,
hash_value,
sql_text
from  gv$sqlarea
where buffer_gets > 50000
order by buffer_gets desc) a
where rownum < 11
/

PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 10 SQL statements present in cache (LIOs or BufferReads)|
PROMPT | Sorted on the basis of BUFFER GETS PER EXECUTION                       |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: Overall top SQLs on the basis on Memmory Reads or L-Reads |
PROMPT | Most probably queries coming under this section are the ones doing FTS |
PROMPT | and might be waiting for any latch/Mutex to gain access on block. Pleas|
PROMPT | check the value of column 'gets_per_exec' that means average memory    |
PROMPT | reads per execution.                                                   |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select rownum as rank, a.*
from (
select buffer_gets, inst_id,
executions,
buffer_gets/ decode(executions,0,1, executions) gets_per_exec,
hash_value,
sql_text
from  gv$sqlarea
where buffer_gets > 50000
order by gets_per_exec desc) a
where rownum < 11
/


PROMPT +----------------------------------------------------------------------------------------------+
PROMPT | Report   : SQLs with the highest concurrency waits (possible latch / mutex-related)          |
PROMPT | This is RAC aware script                                                                     |
PROMPT | Description: Queries sorted basis on concurrency events i.e. Latching or Mutex waits         |
PROMPT | look out for Conc Time (ms) and  SQL Conc Time% columns.
PROMPT | Instance : &current_instance                                                                 |
PROMPT +----------------------------------------------------------------------------------------------+


column sql_text format a40 heading "SQL Text"
column con_time_ms format 99,999,999 heading "Conc Time (ms)"
column con_time_pct format 999.99 heading "SQL Conc | Time%"
column pct_of_con_time format 999.99 heading "% Tot | ConcTime"

WITH sql_conc_waits AS
    (SELECT sql_id, SUBSTR (sql_text, 1, 80) sql_text, inst_id,
            concurrency_wait_time / 1000 con_time_ms,
            elapsed_time,
            ROUND (concurrency_wait_Time * 100 /
                elapsed_time, 2) con_time_pct,
            ROUND (concurrency_wait_Time * 100 /
                SUM (concurrency_wait_Time) OVER (), 2) pct_of_con_time,
            RANK () OVER (ORDER BY concurrency_wait_Time DESC)
       FROM gv$sql
      WHERE elapsed_time> 0)
SELECT sql_text, con_time_ms, con_time_pct, inst_id,
       pct_of_con_time
FROM sql_conc_waits
WHERE rownum <= 10
;



PROMPT +---------------------------------------------------------------------------------------+
PROMPT | Report   : Current CPU Intensive statements (current 15)                              |
PROMPT | This is RAC aware script                                                              |
PROMPT | Instance : &current_instance                                                          |
PROMPT | Description: This gives you expensive SQLs which are in run right now and consuming   |
PROMPT | huge CPU seconds. Check column CPU_USAGE_SECONDS and investigate using SQLID          |
PROMPT +---------------------------------------------------------------------------------------+

set pages 1000
set lines 1000
col OSPID for a06
col SID for 99999
col SERIAL# for 999999
col SQL_ID for a14
col USERNAME for a15
col PROGRAM for a20
col MODULE for a18
col OSUSER for a10
col MACHINE for a25
select * from (
select p.spid "ospid",
(se.SID),ss.serial#,ss.inst_id,ss.SQL_ID,ss.username,ss.program,ss.module,ss.osuser,ss.MACHINE,ss.status,
se.VALUE/100 cpu_usage_seconds
from
gv$session ss,
gv$sesstat se,
gv$statname sn,
gv$process p
where
se.STATISTIC# = sn.STATISTIC#
and
NAME like '%CPU used by this session%'
and
se.SID = ss.SID
and ss.username !='SYS' and
ss.status='ACTIVE'
and ss.username is not null
and ss.paddr=p.addr and value > 0
order by se.VALUE desc)
where rownum <16;


PROMPT +---------------------------------------------------------------------------------------+
PROMPT | Report   : Top 10 CPU itensive queries based on total cpu seconds spend               |
PROMPT | This is RAC aware script                                                              |
PROMPT | Instance : &current_instance                                                          |
PROMPT +---------------------------------------------------------------------------------------+

col SQL_TEXT for a99
select rownum as rank, a.*
from (
select cpu_time/1000000 cpu_time, inst_id,
executions,
buffer_gets,
disk_reads,
cpu_time
hash_value,
sql_text
from  gv$sqlarea
where cpu_time/1000000 > 5
order by cpu_time desc) a
where rownum < 11
/


PROMPT +---------------------------------------------------------------------------------------+
PROMPT | Report   : Top 10 CPU itensive queries based on total cpu seconds spend per execution |
PROMPT | This is RAC aware script                                                              |
PROMPT | Instance : &current_instance                                                          |
PROMPT +---------------------------------------------------------------------------------------+

select rownum as rank, a.*
from (
select cpu_time/1000000 cpu_time, inst_id,
executions,
cpu_time / (1000000 * decode(executions,0,1, executions)) ctime_per_exec,
buffer_gets,
disk_reads,
cpu_time
hash_value,
sql_text
from  gv$sqlarea
where cpu_time/1000000 > 5
order by ctime_per_exec desc) a
where rownum < 11
/


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : LONG OPS                                                    |
PROMPT | This is RAC aware script                                               |
PROMPT | Description: This view displays the status of various operations that  |
PROMPT | run for longer than 6 seconds (in absolute time). These operations     |
PROMPT | currently include many backup and recovery functions, statistics gather|
prompt | , and query execution, and more operations are added for every OracleRE|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

set lines 120
cle bre
col sid form 99999
col start_time head "Start|Time" form a12 trunc
col opname head "Operation" form a12 trunc
col target head "Object" form a30 trunc
col totalwork head "Total|Work" form 9999999999 trunc
col Sofar head "Sofar" form 9999999999 trunc
col elamin head "Elapsed|Time|(Mins)" form 99999999 trunc
col tre head "Time|Remain|(Mins)" form 999999999 trunc

select sid,serial#,to_char(start_time,'dd-mon:hh24:mi') start_time,
          opname,target,totalwork,sofar,(elapsed_Seconds/60) elamin,
          time_remaining tre
 from v$session_longops
 where totalwork <> SOFAR
 order by 9 desc;
/



PROMPT +----------------------------------------------------------------------------------------------+
PROMPT | Report   : IO wait breakdown in the datbase during runtime of this script                    |
PROMPT | This is RAC aware script                                                                     |
PROMPT | Desc: Look for last three cols, TOTAL_WAITS, TIME_WAITED_SECONDS and PCT. Rank matters here  |
PROMPT | Instance : &current_instance                                                                 |
PROMPT +----------------------------------------------------------------------------------------------+

column wait_type format a35
column lock_name format a12
column time_waited_seconds format 999,999.99
column pct format 99.99
set linesize 400 pagesize 400

WITH system_event AS
    (SELECT CASE
              WHEN event LIKE  'direct path% temp' THEN
                 'direct path read / write temp'
              WHEN event LIKE 'direct path%' THEN
                 'direct path read / write non-temp'
              WHEN wait_class = 'User I / O' THEN
                  event
              ELSE wait_class
              END AS wait_type, e. *
            FROM gv$system_event e)
SELECT wait_type, SUM (total_waits) total_waits,
       ROUND (SUM (time_waited_micro) / 1000000, 2) time_waited_seconds,
       ROUND (SUM (time_waited_micro)
             * 100
             / SUM (SUM (time_waited_micro)) OVER (), 2)
          pct
FROM (SELECT wait_type, event, total_waits, time_waited_micro
      FROM system_event e
      UNION
      SELECT 'CPU', stat_name, NULL, VALUE
      FROM gv$sys_time_model
      WHERE stat_name IN ('background cpu time', 'CPU DB')) l
WHERE wait_type <> 'Idle'
GROUP BY wait_type
ORDER BY 4 DESC
/



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Current waits and counts                                    |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This script shows what all sessions waits currently   their count|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

select event, state, inst_id, count(*) from gv$session_wait group by event, state, inst_id order by 4 desc;

set numwidth 10
column event format a25 tru
select inst_id, event, time_waited, total_waits, total_timeouts
from (select inst_id, event, time_waited, total_waits, total_timeouts
from gv$system_event where event not in ('rdbms ipc message','smon timer',
'pmon timer', 'SQL*Net message from client','lock manager wait for remote message',
'ges remote message', 'gcs remote message', 'gcs for action', 'client message',
'pipe get', 'null event', 'PX Idle Wait', 'single-task message',
'PX Deq: Execution Msg', 'KXFQ: kxfqdeq - normal deqeue',
'listen endpoint status','slave wait','wakeup time manager')
order by time_waited desc)
where rownum < 11
order by time_waited desc;


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : IN-FLIGHT TRANSACTION                                       |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This output gives a glimpse of what all running/waiting in DB    |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

set linesize 400 pagesize 400
select x.inst_id,x.sid
,x.serial#
,x.username
,x.sql_id
,plan_hash_value
,sqlarea.DISK_READS
,sqlarea.BUFFER_GETS
,sqlarea.ROWS_PROCESSED
,x.event
,x.osuser
,x.status
,x.BLOCKING_SESSION_STATUS
,x.BLOCKING_INSTANCE
,x.BLOCKING_SESSION
,x.process
,x.machine
,x.OSUSER
,x.program
,x.module
,x.action
,TO_CHAR(x.LOGON_TIME, 'MM-DD-YYYY HH24:MI:SS') logontime
,x.LAST_CALL_ET
--,x.BLOCKING_SESSION_STATUS
,x.SECONDS_IN_WAIT
,x.state
,sql_text,
ltrim(to_char(floor(x.LAST_CALL_ET/3600), '09')) || ':'
 || ltrim(to_char(floor(mod(x.LAST_CALL_ET, 3600)/60), '09')) || ':'
 || ltrim(to_char(mod(x.LAST_CALL_ET, 60), '09'))    RUNNING_SINCE
from   gv$sqlarea sqlarea
,gv$session x
where  x.sql_hash_value = sqlarea.hash_value
and    x.sql_address    = sqlarea.address
and    sql_text not like '%select x.inst_id,x.sid ,x.serial# ,x.username ,x.sql_id ,plan_hash_value ,sqlarea.DISK_READS%'
and    x.status='ACTIVE'
and x.USERNAME is not null
and x.SQL_ADDRESS    = sqlarea.ADDRESS
and x.SQL_HASH_VALUE = sqlarea.HASH_VALUE
order by RUNNING_SINCE desc;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Temp or Sort segment usage                                  |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Queies consuming huge sort area from last 2 hrs and more than 5GB|    |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
select sql_id,max(TEMP_SPACE_ALLOCATED)/(1024*1024*1024) gig
from DBA_HIST_ACTIVE_SESS_HISTORY
where
sample_time > sysdate - (120/1440) and
TEMP_SPACE_ALLOCATED > (5*1024*1024*1024)
group by sql_id order by gig desc;




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Who is doing what with TEMP segments or tablespace          |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Look for cols usage_mb and sql_id and sql_text and username      |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
SELECT sysdate "TIME_STAMP", vsu.username, vs.sid, vp.spid, vs.sql_id, vst.sql_text, vsu.tablespace,
       sum_blocks*dt.block_size/1024/1024 usage_mb
   FROM
   (
           SELECT username, sqladdr, sqlhash, sql_id, tablespace, session_addr,
-- sum(blocks)*8192/1024/1024 "USAGE_MB",
                sum(blocks) sum_blocks
           FROM gv$sort_usage
           HAVING SUM(blocks)> 1000
           GROUP BY username, sqladdr, sqlhash, sql_id, tablespace, session_addr
   ) "VSU",
   gv$sqltext vst,
   gv$session vs,
   gv$process vp,
   dba_tablespaces dt
WHERE vs.sql_id = vst.sql_id
-- AND vsu.sqladdr = vst.address
-- AND vsu.sqlhash = vst.hash_value
   AND vsu.session_addr = vs.saddr
   AND vs.paddr = vp.addr
   AND vst.piece = 0
   AND dt.tablespace_name = vsu.tablespace
order by usage_mb;



SET TERMOUT OFF;
COLUMN current_instance NEW_VALUE current_instance NOPRINT;
SELECT rpad(instance_name, 17) current_instance FROM v$instance;
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
set linesize 400 pagesize 400
SET TERMOUT ON;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Table Level Locking session details                         |
PROMPT | This is RAC aware script and will show all instances of TM Level RLCon |
PROMPT | Desc: This output shows what all active sessions waiting on TM Content.|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

set linesize 400 pagesize 400
select x.inst_id,x.sid
,x.serial#
,x.username
,x.sql_id
,x.event
,x.osuser
,x.status
,x.process
,x.machine
,x.OSUSER
,x.program
,x.module
,x.action
,TO_CHAR(x.LOGON_TIME, 'MM-DD-YYYY HH24:MI:SS') logontime
,x.LAST_CALL_ET
,x.SECONDS_IN_WAIT
,x.state
,sql_text,
ltrim(to_char(floor(x.LAST_CALL_ET/3600), '09')) || ':'
 || ltrim(to_char(floor(mod(x.LAST_CALL_ET, 3600)/60), '09')) || ':'
 || ltrim(to_char(mod(x.LAST_CALL_ET, 60), '09'))    RUNT
from   gv$sqlarea sqlarea
,gv$session x
where  x.sql_hash_value = sqlarea.hash_value
and    x.sql_address    = sqlarea.address
and    x.status='ACTIVE'
and x.event like '%TM - contention%'
and x.USERNAME is not null
and x.SQL_ADDRESS    = sqlarea.ADDRESS
and x.SQL_HASH_VALUE = sqlarea.HASH_VALUE
order by runt desc;




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Row Level Locking session details                           |                  |
PROMPT | This is RAC aware script and will show all instances of TX Level RLCon |
PROMPT | Desc: This output shows what all active sessions waiting on TX Content.|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

set linesize 400 pagesize 400
select x.inst_id,x.sid
,x.serial#
,x.username
,x.sql_id
,x.event
,x.osuser
,x.status
,x.process
,x.machine
,x.OSUSER
,x.program
,x.module
,x.action
,TO_CHAR(x.LOGON_TIME, 'MM-DD-YYYY HH24:MI:SS') logontime
,x.LAST_CALL_ET
,x.SECONDS_IN_WAIT
,x.state
,sql_text,
ltrim(to_char(floor(x.LAST_CALL_ET/3600), '09')) || ':'
 || ltrim(to_char(floor(mod(x.LAST_CALL_ET, 3600)/60), '09')) || ':'
 || ltrim(to_char(mod(x.LAST_CALL_ET, 60), '09'))    RUNT
from   gv$sqlarea sqlarea
,gv$session x
where  x.sql_hash_value = sqlarea.hash_value
and    x.sql_address    = sqlarea.address
and    x.status='ACTIVE'
and x.event like '%row lock contention%'
and x.USERNAME is not null
and x.SQL_ADDRESS    = sqlarea.ADDRESS
and x.SQL_HASH_VALUE = sqlarea.HASH_VALUE
order by runt desc;


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Blocking Tree                                               |
PROMPT | This output helps a DBA to identify all parent lockers in a pedigree   |
PROMPT | Desc: Creates a ASCII tree or graph to show parent and child lockers   |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
col LOCK_TREE for a10
with lk as (select blocking_instance||'.'||blocking_session blocker, inst_id||'.'||sid waiter
 from gv$session where blocking_instance is not null and blocking_session is not null and username is not null)
 select lpad(' ',2*(level-1))||waiter lock_tree from
 (select * from lk
 union all
 select distinct 'root', blocker from lk
 where blocker not in (select waiter from lk))
 connect by prior waiter=blocker start with blocker='root';





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : TX Row Lock Contention Details                              |
PROMPT | This report or result shows some extra and  imp piece of data          |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
col LOCK_MODE for a10
col OBJECT_NAME for a30
col SID_SERIAL for a19
col OSUSER for a9
col USER_STATUS for a14

SELECT DECODE (l.BLOCK, 0, 'Waiting', 'Blocking ->') user_status
,CHR (39) || s.SID || ',' || s.serial# || CHR (39) sid_serial
,(SELECT instance_name FROM gv$instance WHERE inst_id = l.inst_id)
conn_instance
,s.SID
,s.PROGRAM
,s.inst_id
,s.osuser
,s.machine
,DECODE (l.TYPE,'RT', 'Redo Log Buffer','TD', 'Dictionary'
,'TM', 'DML','TS', 'Temp Segments','TX', 'Transaction'
,'UL', 'User','RW', 'Row Wait',l.TYPE) lock_type
--,id1
--,id2
,DECODE (l.lmode,0, 'None',1, 'Null',2, 'Row Share',3, 'Row Excl.'
,4, 'Share',5, 'S/Row Excl.',6, 'Exclusive'
,LTRIM (TO_CHAR (lmode, '990'))) lock_mode
,ctime
--,DECODE(l.BLOCK, 0, 'Not Blocking', 1, 'Blocking', 2, 'Global') lock_status
,object_name
FROM
   gv$lock l
JOIN
   gv$session s
ON (l.inst_id = s.inst_id
AND l.SID = s.SID)
JOIN gv$locked_object o
ON (o.inst_id = s.inst_id
AND s.SID = o.session_id)
JOIN dba_objects d
ON (d.object_id = o.object_id)
WHERE (l.id1, l.id2, l.TYPE) IN (SELECT id1, id2, TYPE
FROM gv$lock
WHERE request > 0)
ORDER BY id1, id2, ctime DESC;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : What is blocking what .....                                 |
PROMPT | This is that old and popular simple output that everybody knows        |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
select l1.sid, ' IS BLOCKING ', l2.sid
from gv$lock l1, gv$lock l2 where l1.block =1 and l2.request > 0
and l1.id1=l2.id1
and l1.id2=l2.id2;




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Some more on locking                                        |
PROMPT | Little more formatted data that abive output                           |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
col BLOCKING_STATUS for a120
select s2.inst_id,s1.username || '@' || s1.machine
 || ' ( SID=' || s1.sid || ' )  is blocking '
 || s2.username || '@' || s2.machine || ' ( SID=' || s2.sid || ' ) ' AS blocking_status
  from gv$lock l1, gv$session s1, gv$lock l2, gv$session s2
  where s1.sid=l1.sid and s2.sid=l2.sid and s1.inst_id=l1.inst_id and s2.inst_id=l2.inst_id
  and l1.BLOCK=1 and l2.request > 0
  and l1.id1 = l2.id1
  and l2.id2 = l2.id2
order by s1.inst_id;


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : More on locks to read and analyze                           |
PROMPT | Thidata you can use for your deep drill down                         |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
col BLOCKER for a8
col WAITER for a10
col LMODE for a14
col REQUEST for a15

SELECT sid,
                                TYPE,
                                DECODE( block, 0, 'NO', 'YES' ) BLOCKER,
        DECODE( request, 0, 'NO', 'YES' ) WAITER,
        decode(LMODE,1,'    ',2,'RS',3,'RX',4,'S',5,'SRX',6,'X','NONE') lmode,
                                 decode(REQUEST,1,'    ',2,'RS',3,'RX',4,'S',5,'SRX',6,'X','NONE') request,
                                TRUNC(CTIME/60) MIN ,
                                ID1,
                                ID2,
        block
                        FROM  gv$lock
      where request > 0 OR block =1;








PROMPT +---------------------------------------------------------------------------------------+
PROMPT | Report   : Database Objects Experienced the Most Number of Waits in the Past One Hour |
PROMPT | This is RAC aware script                                                              |
PROMPT | Description: Look for EVENT its getting and last column TTL_WAIT_TIME, time waited   |
PROMPT | Instance : &current_instance                                                          |
PROMPT +---------------------------------------------------------------------------------------+

col event format a40
col object_name format a40

select * from
(
  select dba_objects.object_name,
 dba_objects.object_type,
active_session_history.event,
 sum(active_session_history.wait_time +
  active_session_history.time_waited) ttl_wait_time
from gv$active_session_history active_session_history,
    dba_objects
 where
active_session_history.sample_time between sysdate - 1/24 and sysdate
and active_session_history.current_obj# = dba_objects.object_id
 group by dba_objects.object_name, dba_objects.object_type, active_session_history.event
 order by 4 desc)
where rownum < 6;




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : GLOBAL CACHE CR PERFORMANCE                                 |
PROMPT | Desc: This shows the average latency of a consistent block request.    |
PROMPT | AVG CR BLOCK RECEIVE TIME should typically be about 15 milliseconds    |
PROMPT | This is RAC aware script                                               |
PROMPT +------------------------------------------------------------------------+


set numwidth 20
column "AVG CR BLOCK RECEIVE TIME (ms)" format 9999999.9
select b1.inst_id, b2.value "GCS CR BLOCKS RECEIVED",
b1.value "GCS CR BLOCK RECEIVE TIME",
((b1.value / b2.value) * 10) "AVG CR BLOCK RECEIVE TIME (ms)"
from gv$sysstat b1, gv$sysstat b2
where b1.name = 'global cache cr block receive time' and
b2.name = 'global cache cr blocks received' and b1.inst_id = b2.inst_id
or b1.name = 'gc cr block receive time' and
b2.name = 'gc cr blocks received' and b1.inst_id = b2.inst_id ;





PROMPT +----------------------------------------------------------------------------------------------+
PROMPT | Report   : RAC Lost blocks report plus GC specific events                                    |
PROMPT | This is RAC aware script                                                                     |
PROMPT | Desc: This shows all RAC specific metrics like block lost, blocks served and recieved        |
PROMPT | Instance : &current_instance                                                                 |
PROMPT +----------------------------------------------------------------------------------------------+

col name format a30

SELECT name, SUM (VALUE) value
FROM gv$sysstat
WHERE name LIKE 'gc% lost'
      OR name LIKE 'gc% received'
      OR name LIKE 'gc% served'
GROUP BY name
ORDER BY name;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Wait Chains in RAC systems                                  |
PROMPT | Desc: This will show you the top 100 wait chain processes at any given |
PROMPT | point.You should look for number of waiters and blocking process       |
PROMPT | This is RAC aware script and only works with 11g and up versions       |
PROMPT +------------------------------------------------------------------------+

set pages 1000
set lines 120
column w_proc format a50 tru
column instance format a20 tru
column inst format a28 tru
column wait_event format a50 tru
column p1 format a16 tru
column p2 format a16 tru
column p3 format a15 tru
column Seconds format a50 tru
column sincelw format a50 tru
column blocker_proc format a50 tru
column waiters format a50 tru
column chain_signature format a100 wra
column blocker_chain format a100 wra
SELECT *
FROM (SELECT 'Current Process: '||osid W_PROC, 'SID '||i.instance_name INSTANCE,
'INST #: '||instance INST,'Blocking Process: '||decode(blocker_osid,null,'<none>',blocker_osid)||
' from Instance '||blocker_instance BLOCKER_PROC,'Number of waiters: '||num_waiters waiters,
'Wait Event: ' ||wait_event_text wait_event, 'P1: '||p1 p1, 'P2: '||p2 p2, 'P3: '||p3 p3,
'Seconds in Wait: '||in_wait_secs Seconds, 'Seconds Since Last Wait: '||time_since_last_wait_secs sincelw,
'Wait Chain: '||chain_id ||': '||chain_signature chain_signature,'Blocking Wait Chain: '||decode(blocker_chain_id,null,
'<none>',blocker_chain_id) blocker_chain
FROM v$wait_chains wc,
v$instance i
WHERE wc.instance = i.instance_number (+)
AND ( num_waiters > 0
OR ( blocker_osid IS NOT NULL
AND in_wait_secs > 10 ) )
ORDER BY chain_id,
num_waiters DESC)
WHERE ROWNUM < 101;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Latch statistics 1                                          |
PROMPT | This is RAC aware script                                               |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+


select inst_id, name latch_name,
round((gets-misses)/decode(gets,0,1,gets),3) hit_ratio,
round(sleeps/decode(misses,0,1,misses),3) "SLEEPS/MISS"
from gv$latch
where round((gets-misses)/decode(gets,0,1,gets),3) < .99
and gets != 0
order by round((gets-misses)/decode(gets,0,1,gets),3);



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Latch status                                                |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Please look for cols WAIT_TIME_SECONDS and WAIT_TIME             |
PROMPT |     Critical if both of the numbers are high                           |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

col NAME for a50
select v.*
from
  (select
      name, inst_id,
      gets,
      misses,
      round(misses*100/(gets+1), 3) misses_gets_pct,
      spin_gets,
      sleep1,
      wait_time,
      round(wait_time/1000000) wait_time_seconds,
   rank () over
     (order by wait_time desc) as misses_rank
   from
      gv$latch
   where gets + misses + sleep1 + wait_time > 0
   order by
      wait_time desc
  ) v
where
   misses_rank <= 10;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : No Willing to wait mode latch stats                         |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This section is for those latches who requests in immediate_gets |
PROMPT | mode. Look for SLEEPSMISS column which is last one in results                  |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
select inst_id, name latch_name,
round((immediate_gets/(immediate_gets+immediate_misses)), 3) hit_ratio,
round(sleeps/decode(immediate_misses,0,1,immediate_misses),3) "SLEEPS/MISS"
from gv$latch
where round((immediate_gets/(immediate_gets+immediate_misses)), 3) < .99
and immediate_gets + immediate_misses > 0
order by round((immediate_gets/(immediate_gets+immediate_misses)), 3);






PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : SQL with 100 or more unshared child cursors                 |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Results coming here with more than 500 childs can lead to high   |
PROMPT | hard parsing situations which could lead to Library cache latching issu|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

WITH
not_shared AS (
SELECT /*+  MATERIALIZE NO_MERGE  */ /* 2a.135 */
       sql_id, COUNT(*) child_cursors,
       RANK() OVER (ORDER BY COUNT(*) DESC NULLS LAST) AS sql_rank
  FROM gv$sql_shared_cursor
 GROUP BY
       sql_id
HAVING COUNT(*) > 99
)
SELECT /*+  NO_MERGE  */ /* 2a.135 */
       ns.sql_rank,
       ns.child_cursors,
       ns.sql_id,
       (SELECT s.sql_text FROM gv$sql s WHERE s.sql_id = ns.sql_id AND ROWNUM = 1) sql_text
  FROM not_shared ns
 ORDER BY
       ns.sql_rank,
       ns.child_cursors DESC,
       ns.sql_id;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Sesions Waiting                                             |
PROMPT | Desc: The entries that are shown at the top are the sessions that have |
PROMPT | waited the longest amount of time that are waiting for non-idle wait   |
PROMPT | events (event column).
PROMPT | This is RAC aware script                                               |
PROMPT +------------------------------------------------------------------------+


set numwidth 15
set heading on
column state format a7 tru
column event format a25 tru
column last_sql format a40 tru
select sw.inst_id, sa.sql_id,sw.sid, sw.state, sw.event, sw.seconds_in_wait seconds,
sw.p1, sw.p2, sw.p3, sa.sql_text last_sql
from gv$session_wait sw, gv$session s, gv$sqlarea sa
where sw.event not in
('rdbms ipc message','smon timer','pmon timer',
'SQL*Net message from client','lock manager wait for remote message',
'ges remote message', 'gcs remote message', 'gcs for action', 'client message',
'pipe get', 'null event', 'PX Idle Wait', 'single-task message',
'PX Deq: Execution Msg', 'KXFQ: kxfqdeq - normal deqeue',
'listen endpoint status','slave wait','wakeup time manager')
and sw.seconds_in_wait > 0
and (sw.inst_id = s.inst_id and sw.sid = s.sid)
and (s.inst_id = sa.inst_id and s.sql_address = sa.address)
order by seconds desc;






PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Archive generation per hour basis                           |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This will give an idea about any spike in redo activity or DMLs  |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+
set linesize 140
set feedback off
set timing off
set pagesize 1000
col ARCHIVED format a8
col ins    format 99  heading "DB"
col member format a80
col status format a12
col archive_date format a20
col member format a60
col type   format a10
col group#  format 99999999
col min_archive_interval format a20
col max_archive_interval format a20
col h00 heading "H00" format  a3
col h01 heading "H01" format  a3
col h02 heading "H02" format  a3
col h03 heading "H03" format  a3
col h04 heading "H04" format  a3
col h05 heading "H05" format  a3
col h06 heading "H06" format  a3
col h07 heading "H07" format  a3
col h08 heading "H08" format  a3
col h09 heading "H09" format  a3
col h10 heading "H10" format  a3
col h11 heading "H11" format  a3
col h12 heading "H12" format  a3
col h13 heading "H13" format  a3
col h14 heading "H14" format  a3
col h15 heading "H15" format  a3
col h16 heading "H16" format  a3
col h17 heading "H17" format  a3
col h18 heading "H18" format  a3
col h19 heading "H19" format  a3
col h20 heading "H20" format  a3
col h21 heading "H21" format  a3
col h22 heading "H22" format  a3
col h23 heading "H23" format  a3
col total format a6
col date format a10

select * from v$logfile order by group#;
select * from v$log order by SEQUENCE#;

select max( sequence#) last_sequence, max(completion_time) completion_time, max(block_size) block_size from v$archived_log ;

SELECT instance ins,
       log_date "DATE" ,
       lpad(to_char(NVL( COUNT( * ) , 0 )),6,' ') Total,
       lpad(to_char(NVL( SUM( decode( log_hour , '00' , 1 ) ) , 0 )),3,' ') h00 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '01' , 1 ) ) , 0 )),3,' ') h01 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '02' , 1 ) ) , 0 )),3,' ') h02 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '03' , 1 ) ) , 0 )),3,' ') h03 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '04' , 1 ) ) , 0 )),3,' ') h04 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '05' , 1 ) ) , 0 )),3,' ') h05 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '06' , 1 ) ) , 0 )),3,' ') h06 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '07' , 1 ) ) , 0 )),3,' ') h07 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '08' , 1 ) ) , 0 )),3,' ') h08 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '09' , 1 ) ) , 0 )),3,' ') h09 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '10' , 1 ) ) , 0 )),3,' ') h10 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '11' , 1 ) ) , 0 )),3,' ') h11 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '12' , 1 ) ) , 0 )),3,' ') h12 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '13' , 1 ) ) , 0 )),3,' ') h13 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '14' , 1 ) ) , 0 )),3,' ') h14 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '15' , 1 ) ) , 0 )),3,' ') h15 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '16' , 1 ) ) , 0 )),3,' ') h16 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '17' , 1 ) ) , 0 )),3,' ') h17 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '18' , 1 ) ) , 0 )),3,' ') h18 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '19' , 1 ) ) , 0 )),3,' ') h19 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '20' , 1 ) ) , 0 )),3,' ') h20 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '21' , 1 ) ) , 0 )),3,' ') h21 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '22' , 1 ) ) , 0 )),3,' ') h22 ,
       lpad(to_char(NVL( SUM( decode( log_hour , '23' , 1 ) ) , 0 )),3,' ') h23
FROM   (
        SELECT thread# INSTANCE ,
               TO_CHAR( first_time , 'YYYY-MM-DD' ) log_date ,
               TO_CHAR( first_time , 'hh24' ) log_hour
        FROM   v$log_history
       )
GROUP  BY
       instance,log_date
ORDER  BY
       log_date ;

select trunc(min(completion_time - first_time))||'  Day  '||
       to_char(trunc(sysdate,'dd') + min(completion_time - first_time),'hh24:mm:ss')||chr(10) min_archive_interval,
       trunc(max(completion_time - first_time))||'  Day  '||
       to_char(trunc(sysdate,'dd') + max(completion_time - first_time),'hh24:mm:ss')||chr(10) max_archive_interval
from gv$archived_log
where sequence# <> ( select max(sequence#) from gv$archived_log ) ;

set feedback on
set timing on




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : SESSION DETAILS                                             |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Shows details about all sessions and their states active, inactiv|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------+

set linesize 400 pagesize 400
select resource_name, current_utilization, max_utilization, limit_value, inst_id
    from gv$resource_limit
    where resource_name in ('sessions', 'processes');


select count(s.status) INACTIVE_SESSIONS
from gv$session s, gv$process p
where
p.addr=s.paddr and
s.status='INACTIVE';


select count(s.status) "INACTIVE SESSIONS > 3HOURS "
from gv$session s, gv$process p
where
p.addr=s.paddr and
s.last_call_et > 10800 and
s.status='INACTIVE';



select count(s.status) ACTIVE_SESSIONS
from gv$session s, gv$process p
where
p.addr=s.paddr and
s.status='ACTIVE';


select s.program,count(s.program) Inactive_Sessions_from_1Hour
from gv$session s,gv$process p
where     p.addr=s.paddr  AND
s.status='INACTIVE'
and s.last_call_et > (10800)
group by s.program
order by 2 desc;


set linesize 400 pagesize 400
col INST_ID for 99
col spid for a10
set linesize 150
col PROGRAM for a10
col action format a10
col logon_time format a16
col module format a13
col cli_process format a7
col cli_mach for a15
col status format a10
col username format a10
col last_call_et_Hrs for 9999.99
col sql_hash_value for 9999999999999
col username for a10
set linesize 152
set pagesize 80
col "Last SQL" for a60
col elapsed_time for 999999999999

select p.spid, s.sid,s.serial#,s.last_call_et/3600 last_call_et_3Hrs ,s.status,s.action,s.module,s.program,t.disk_reads,lpad(t.sql_text,30) "Last SQL"
from gv$session s, gv$sqlarea t,gv$process p
where s.sql_address =t.address and
s.sql_hash_value =t.hash_value and
p.addr=s.paddr and
s.status='INACTIVE'
and s.last_call_et > (10800)
order by last_call_et;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Lists all locked objects for whole RAC.                     |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Remember to always look for X type locks, SS, SX, S, SSX are fine|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

SET LINESIZE 500
SET PAGESIZE 1000
SET VERIFY OFF

COLUMN owner FORMAT A20
COLUMN username FORMAT A20
COLUMN object_owner FORMAT A20
COLUMN object_name FORMAT A30
COLUMN locked_mode FORMAT A15

SELECT b.inst_id,
       b.session_id AS sid,
       NVL(b.oracle_username, '(oracle)') AS username,
       a.owner AS object_owner,
       a.object_name,
       Decode(b.locked_mode, 0, 'None',
                             1, 'Null (NULL)',
                             2, 'Row-S (SS)',
                             3, 'Row-X (SX)',
                             4, 'Share (S)',
                             5, 'S/Row-X (SSX)',
                             6, 'Exclusive (X)',
                             b.locked_mode) locked_mode,
       b.os_user_name
FROM   dba_objects a,
       gv$locked_object b
WHERE  a.object_id = b.object_id
ORDER BY 1, 2, 3, 4;







PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Undo usage report                                           |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This shows details about all undo rollback segments, best for 01555|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

SET LINESIZE 200

COLUMN username FORMAT A15

SELECT s.inst_id,
       s.username,
       s.sid,
       s.serial#,
       t.used_ublk,
       t.used_urec,
       rs.segment_name,
       r.rssize,
       r.status
FROM   gv$transaction t,
       gv$session s,
       gv$rollstat r,
       dba_rollback_segs rs
WHERE  s.saddr = t.ses_addr
AND    s.inst_id = t.inst_id
AND    t.xidusn = r.usn
AND    t.inst_id = r.inst_id
AND    rs.segment_id = t.xidusn
ORDER BY t.used_ublk DESC;





PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Local Enqueues                                              |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: This section will show us if there are any local enqueues.       |
PROMPT | The addr column will show the lock address. The type will show the type|
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

set numwidth 12
column event format a12 tru
select l.inst_id, l.sid, l.addr, l.type, l.id1, l.id2,
decode(l.block,0,'blocked',1,'blocking',2,'global') block,
sw.event, sw.seconds_in_wait sec
from gv$lock l, gv$session_wait sw
where (l.sid = sw.sid and l.inst_id = sw.inst_id)
and l.block in (0,1)
order by l.type, l.inst_id, l.sid;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : ORA errors reported in alert log of databases, SYSDATE-1    |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Shows all alert log ora errors and log files with locations      |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

select TO_CHAR(A.ORIGINATING_TIMESTAMP, 'dd.mm.yyyy hh24:mi:ss') MESSAGE_TIME
,inst_id, message_text
,host_id
,inst_id
,adr_home
from v$DIAG_ALERT_EXT A
where A.ORIGINATING_TIMESTAMP > sysdate-1
and component_id='rdbms'
and message_text like '%ORA-%'
order by 1 desc;

spool off
exit


PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top object waits in the database.    |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Shows Object name along with count, sqlid, and total time waited |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|


set lines 170 echo off
col event       format a26      head 'Wait Event'       trunc
col mod         format a26      head 'Module'           trunc
col sqlid       format a13      head 'SQL Id'
col oname       format a38      head 'Object Name'
col sname       format a30      head 'SubObject Name'
col otyp        format a10      head 'Object Typ'       trunc
col cnt         format 999999   head 'Wait Cnt'
col twait       format 9999999999       head 'Tot Time|Waited'

select   o.owner||'.'||o.object_name            oname
        ,o.object_type                          otyp
        ,o.subobject_name                       sname
        ,h.event                                event
        ,h.wcount                               cnt
        ,h.twait                                twait
        ,h.sql_id                               sqlid
        ,h.module                               mod
from    (select current_obj#,sql_id,module,event,count(*) wcount,sum(time_waited+wait_time) twait
         from gv$active_session_history
         where event not in (
                       'queue messages'
                      ,'rdbms ipc message'
                      ,'rdbms ipc reply'
                      ,'pmon timer'
                      ,'smon timer'
                      ,'jobq slave wait'
                      ,'wait for unread message on broadcast channel'
                      ,'wakeup time manager')
         and event not like 'SQL*Net%'
         and event not like 'Backup%'
         group by current_obj#,sql_id,module,event
         order by twait desc)     h
        ,dba_objects              o
where    h.current_obj#         = o.object_id
and      rownum                 < 31
;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : list of all custom SQL Profiles in DB                       |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Shows details of all SQL profiles already there in the database  |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

set linesize 400 pagesize 400
col name for a30
col created for a30
select name, created, status,sql_text as SQLTXT from dba_sql_profiles order by created desc;




PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Show active sessions from latest ASH sample   |
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Shows Show active sessions from latest ASH sample                |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

set linesi 290
col hostcpu	format 999.9	head 'Host|Cpu%'
col module	format a15 	head 'Module'		trunc
col sidser	format a15  	head 'Sid,Serial<Blk'
col state	format a07
col objid	format 9999999
col event	format a23	head 'Event'		trunc
col pct		format 999.9	head 'Sid|Cpu%'
col cpu		format 99.999	head 'CPU|ms'
col lreads	format 9999999	head 'Logical|Reads'
col preads	format 999999	head 'Phys|Reads'
col lread_pct	format 99	head 'LR|%'
col pread_pct	format 99	head 'PR|%'
col hparse	format 99	head 'Hard|Parse'
col sparse	format 999	head 'Soft|Parse'
col pgak	format 999,999	head 'PGAk'
col sqlstart	format a05	head 'SQL|Start'
col temp_mb	format 99999	head 'Temp|MB'
col secs_ago	format 999	head 'Sec|Ago'
col opid	format 999	head 'Op|Id'
col oper	format a20	head 'Operation'	trunc
col oname	format a28	head 'Object'		trunc
col sqlidc	format a17	head 'SqlId:Child'
col p1p2p3	format a15	head '   P1:P2:P3'
col sqlop	format a03	head 'Cmd'		trunc
col is_current	format a01	head 'C'

break on hostcpu

with	 ash as
(
select 	 session_id	
	,is_sqlid_current
	,session_serial#
	,session_type
	,event
	,session_state
	,sql_id
	,sql_child_number
	,sql_opname
	,sql_plan_line_id
	,sql_plan_operation
	,sql_plan_options
	,current_obj#	
	,module 
	,machine
	,sql_exec_start
	,temp_space_allocated
	,p1
	,p2
	,p3
from 	 gv$active_session_history 
where	 sample_id	= (select max(sample_id) from gv$active_session_history)
)
select * from
(
select 	 /*+ ordered */
	 ccpu.hostcpu 								hostcpu
	,lpad(ses.sid,4,' ')||','||lpad(ses.serial#,5,' ')||decode(substr(ses.blocking_session_status,1,1),'V','<',' ')||lpad(ses.blocking_session,4,' ')	sidser
	,round(sm.cpu * 100 / sm.intsize_csec, 2) 				pct
	--,sm.logical_reads							lreads
	,sm.logical_read_pct							lread_pct
	--,sm.physical_reads							preads
	,sm.physical_read_pct							pread_pct
	,sm.pga_memory/1024							pgaK
	,least(999,(sysdate-ash.sql_exec_start)*24*60*60)			secs_ago
	,nvl(ash.module,'['||substr(ash.machine,1,instr(ash.machine,'amazon')-2)||']')	module
	,ash.sql_id||decode(ash.sql_id,null,'',':')||decode(ash.sql_child_number,-1,'',ash.sql_child_number) 	sqlidc
	--,ash.is_sqlid_current							is_current
	--,ash.sqlstart
	--,ses.prev_sql_id
	,ash.sql_opname								sqlop
	,decode(ses.state,'WAITING',o.owner||decode(o.object_name,null,null,'.')||o.object_name,null)		oname
	,decode(ash.event,null,'['||ash.session_state||']',ash.event)		event
	,decode(ash.event,null,'',lpad(least(ash.p1,9999),3,' ')||':'||lpad(least(ash.p2,9999999),7,' ')||':'||lpad(least(ash.p3,999),3,' '))	p1p2p3
	,ash.sql_plan_line_id							opid
	,ash.sql_plan_operation||' '||ash.sql_plan_options 			oper
	--,sm.cpu/1000		cpu
	--,sm.hard_parses		hparse
	--,sm.soft_parses		sparse
	--,ash.temp_mb		temp_mb
from 	 ash
	,gv$session	ses
	,gv$sessmetric   sm
	,dba_objects	o
	,(select avg(value) hostcpu from v$sysmetric where METRIC_NAME='Host CPU Utilization (%)') ccpu
where	 ash.session_id		= ses.sid
and	 ash.session_serial# 	= ses.serial#
and      ses.sid        	= sm.session_id
and      ses.serial#    	= sm.session_serial_num
and	 ash.session_id 	= sm.session_id
and	 ash.session_serial# 	= sm.session_serial_num
and	 ash.current_obj#(+)	= o.object_id
)
order by module
	,sqlidc
	,oname
	,event
;



PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : who is using most pga currently over 2MB
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: PGA Usage                |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

col sid		format 99999
col module 	format a60
col kb 		format 999,999,999
col qc 		format a5
col hhmmss 	format a10
col sql_id 	format a13

break on hhmmss on qc skip 1 on sid

select 	 to_char(sample_time,'HH24:MI:SS') 	hhmmss
	,decode(qc_session_id,null,'n/a',qc_session_id) 	qc
	,inst_id,SESSION_ID 				sid
	,PGA_ALLOCATED/1024			kb
	,sql_id					sql_id
	,decode(module,null,'<'||program||'>',module) module
from 	 gv$active_session_history 
where 	 PGA_ALLOCATED > 2*1024*1024
and 	 sample_time > sysdate-3/60/1440 
order by sample_time, qc_session_id, SESSION_ID
/

PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : Top 10 objects in database.
PROMPT | This is RAC aware script                                               |
PROMPT | Desc: Database Usage                |
PROMPT | Instance : &current_instance                                           |
PROMPT +------------------------------------------------------------------------|

col segment_name format a30
col owner format a20
col tablespace_name format a30
select * from (select owner,segment_name,SEGMENT_TYPE,TABLESPACE_NAME,round(sum(BYTES)/(1024*1024*1024)) size_in_GB 
from dba_segments group by owner,segment_name,SEGMENT_TYPE,TABLESPACE_NAME order by 5 desc ) where rownum<=10;

SPOOL OFF;
SET LINESIZE 200
SET PAGESIZE 100
SET MARKUP HTML ON
SPOOL open_cursor_stats.html

PROMPT <h2>Open Cursor Statistics per RAC Instance</h2>

SELECT
    inst_id,
    TO_CHAR(execute_count, '999G999G999G999') AS "SQL Execution",
    TO_CHAR(parse_count, '999G999G999G999') AS "Parse Count",
    TO_CHAR(cursor_hits, '999G999G999G999') AS "Cursor Hits",
    ROUND((parse_count / NULLIF(execute_count, 0)) * 100, 2) AS "Parse % Total",
    ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) AS "Cursor Cache % Total",
    CASE
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 90 THEN 'OK'
        WHEN ROUND((cursor_hits / NULLIF(parse_count, 0)) * 100, 2) >= 80 THEN 'WARNING'
        ELSE 'CRITICAL'
    END AS status
FROM (
    SELECT
        inst_id,
        MAX(CASE WHEN name = 'execute count' THEN value END) AS execute_count,
        MAX(CASE WHEN name = 'parse count (total)' THEN value END) AS parse_count,
        MAX(CASE WHEN name = 'session cursor cache hits' THEN value END) AS cursor_hits
    FROM
        gv$sysstat
    WHERE
        name IN ('execute count', 'parse count (total)', 'session cursor cache hits')
    GROUP BY
        inst_id
)
ORDER BY
    inst_id;

SPOOL OFF;
##
SELECT
    inst_id,
    ROUND(COUNT(*) / (24 * 60 * 60), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (24 * 60 * 60), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time >= SYSDATE - 1
GROUP BY
    inst_id
ORDER BY
    inst_id;
SELECT
    inst_id,
    ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                      EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                      EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                      EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
         ), 2) AS average_active_sessions,
    CASE
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 10 THEN 'CRITICAL'
        WHEN ROUND(COUNT(*) / (EXTRACT(DAY FROM (MAX(sample_time) - MIN(sample_time))) * 24 * 60 * 60 +
                               EXTRACT(HOUR FROM (MAX(sample_time) - MIN(sample_time))) * 60 * 60 +
                               EXTRACT(MINUTE FROM (MAX(sample_time) - MIN(sample_time))) * 60 +
                               EXTRACT(SECOND FROM (MAX(sample_time) - MIN(sample_time)))
             ), 2) >= 5 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM
    gv$active_session_history
WHERE
    sample_time BETWEEN TO_DATE('2025-06-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
                    AND TO_DATE('2025-06-01 23:59:59', 'YYYY-MM-DD HH24:MI:SS')
GROUP BY
    inst_id
ORDER BY
    inst_id;
