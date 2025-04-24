#!/bin/bash

# Usage: ./rac_resize_redologs.sh <input_file> <new_size>
# Example: ./rac_resize_redologs.sh rac_config.txt 1G
# Input file format:
#   primary_scan primary_db
#   standby_scan standby_db

# Check input parameters
if [ $# -ne 2 ]; then
  echo "Usage: $0 <input_file> <new_size>"
  exit 1
fi

INPUT_FILE="$1"
NEW_SIZE="$2"
PRIMARY_HOST=$(awk 'NR==1 {print $1}' "$INPUT_FILE")
PRIMARY_DB=$(awk 'NR==1 {print $2}' "$INPUT_FILE")
STANDBY_HOST=$(awk 'NR==2 {print $1}' "$INPUT_FILE")
STANDBY_DB=$(awk 'NR==2 {print $2}' "$INPUT_FILE")
DG_USER="sys"
LOG_FILE="rac_redolog_resize_$(date +%Y%m%d_%H%M).log"

# Validate input
if [[ -z "$PRIMARY_HOST" || -z "$PRIMARY_DB" || 
      -z "$STANDBY_HOST" || -z "$STANDBY_DB" || -z "$NEW_SIZE" ]]; then
  echo "Invalid input file format. Expected:"
  echo "primary_scan primary_db"
  echo "standby_scan standby_db"
  exit 1
fi

# Get SYS password
read -s -p "Enter SYS password for ${PRIMARY_HOST}/${PRIMARY_DB}: " SYS_PASSWORD
echo

# Function to log messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Verify database role
verify_role() {
  local host=$1
  local db=$2
  local expected_role=$3
  
  role=$(sqlplus -S "${DG_USER}/${SYS_PASSWORD}@//${host}:1521/${db} as sysdba" << EOF
    SET HEADING OFF FEEDBACK OFF PAGESIZE 0
    SELECT database_role FROM v\$database;
    EXIT;
EOF
  )
  if [[ "$role" != "$expected_role" ]]; then
    log "Error: ${host}/${db} is not a ${expected_role} (Role: ${role})"
    exit 1
  fi
  log "${expected_role} database confirmed"
}

# Enhanced online redo log resize with active log handling
resize_online_redologs() {
  local host=$1
  local db=$2
  log "Resizing ONLINE redo logs on ${db} (RAC) to ${NEW_SIZE}..."
  
  sqlplus -S "${DG_USER}/${SYS_PASSWORD}@//${host}:1521/${db} as sysdba" << EOF >> "$LOG_FILE" 2>&1
    SET SERVEROUTPUT ON
    DECLARE
      TYPE thread_t IS TABLE OF NUMBER;
      threads thread_t;
      groups_per_thread NUMBER;
      max_retries NUMBER := 5;
      retry_interval NUMBER := 10; -- seconds
      
      -- Procedure to drop old logs with retries
      PROCEDURE drop_old_logs IS
        CURSOR old_groups_cur IS 
          SELECT group#, thread#, status 
          FROM v\$log 
          WHERE bytes < (SELECT MAX(bytes) FROM v\$log);
      BEGIN
        FOR oldgrp IN old_groups_cur LOOP
          DECLARE
            retries NUMBER := 0;
            current_status VARCHAR2(10);
          BEGIN
            current_status := oldgrp.status;
            
            WHILE current_status != 'INACTIVE' AND retries < max_retries LOOP
              DBMS_OUTPUT.PUT_LINE('Thread ' || oldgrp.thread# || 
                ' Group ' || oldgrp.group# || ' still ' || current_status ||
                ' - forcing log switch (attempt ' || (retries+1) || ')');
                
              -- Force log switch for specific thread
              BEGIN
                EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE THREAD ' || oldgrp.thread#;
              EXCEPTION
                WHEN OTHERS THEN NULL;
              END;
              
              -- Wait for status change
              DBMS_LOCK.SLEEP(retry_interval);
              
              -- Check current status
              BEGIN
                SELECT status INTO current_status
                FROM v\$log
                WHERE group# = oldgrp.group#;
              EXCEPTION
                WHEN OTHERS THEN
                  current_status := 'UNKNOWN';
              END;
              
              retries := retries + 1;
            END LOOP;
            
            IF current_status = 'INACTIVE' THEN
              BEGIN
                EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP ' || oldgrp.group#;
                DBMS_OUTPUT.PUT_LINE('Dropped group ' || oldgrp.group#);
              EXCEPTION
                WHEN OTHERS THEN
                  DBMS_OUTPUT.PUT_LINE('Error dropping group ' || oldgrp.group# || ': ' || SQLERRM);
              END;
            ELSE
              DBMS_OUTPUT.PUT_LINE('Failed to drop group ' || oldgrp.group# || 
                ' - still ' || current_status || ' after ' || max_retries || ' attempts');
            END IF;
          END;
        END LOOP;
      END drop_old_logs;

    BEGIN
      -- Get active threads
      SELECT thread# BULK COLLECT INTO threads FROM v\$thread;

      -- Get current online log groups per thread
      SELECT COUNT(*)/COUNT(DISTINCT thread#) INTO groups_per_thread FROM v\$log;

      -- Add new log groups for each thread
      FOR i IN 1..threads.COUNT LOOP
        FOR j IN 1..groups_per_thread LOOP
          EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE THREAD ' || threads(i) || 
                            ' SIZE ${NEW_SIZE}';
        END LOOP;
      END LOOP;

      -- Force log switches across all threads
      FOR thread_rec IN (SELECT thread# FROM v\$thread) LOOP
        FOR k IN 1..(groups_per_thread * 2) LOOP
          EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE THREAD ' || thread_rec.thread#;
        END LOOP;
      END LOOP;

      -- Drop old logs with retry mechanism
      drop_old_logs;
      
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
    END;
    /
    EXIT;
EOF

  if grep -q "ORA-" "$LOG_FILE"; then
    log "Error resizing online redo logs on ${db}"
    return 1
  fi
  log "Online redo logs resized successfully on ${db} (RAC)"
}

# Other functions remain unchanged (resize_standby_redologs, manage_mrp, etc.)

# Main execution
{
  log "Starting RAC Redo Log Resize Operation"
  verify_role "$PRIMARY_HOST" "$PRIMARY_DB" "PRIMARY"
  verify_role "$STANDBY_HOST" "$STANDBY_DB" "PHYSICAL STANDBY"

  # Process standby
  manage_mrp "OFF"
  manage_standby_file_management "$STANDBY_HOST" "$STANDBY_DB" "MANUAL"
  resize_online_redologs "$STANDBY_HOST" "$STANDBY_DB"
  resize_standby_redologs "$STANDBY_HOST" "$STANDBY_DB"
  manage_standby_file_management "$STANDBY_HOST" "$STANDBY_DB" "AUTO"
  manage_mrp "ON"

  # Process primary
  resize_online_redologs "$PRIMARY_HOST" "$PRIMARY_DB"
  resize_standby_redologs "$PRIMARY_HOST" "$PRIMARY_DB"

  # Verification steps
  log "Operation completed successfully"
} | tee -a "$LOG_FILE"

echo "Detailed log saved to: ${LOG_FILE}"

##########################
#!/bin/bash

# Usage: ./rac_health_scan.sh <input_file>
# Input file format (single line):
#   scan_host db_name

# Check input file
if [ $# -ne 1 ]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

INPUT_FILE="$1"
SCAN_HOST=$(awk '{print $1}' "$INPUT_FILE")
DB_NAME=$(awk '{print $2}' "$INPUT_FILE")
REPORT_FILE="rac_health_$(date +%Y%m%d_%H%M).html"

# Validate input
if [[ -z "$SCAN_HOST" || -z "$DB_NAME" ]]; then
  echo "Invalid input file format. Expected:"
  echo "scan_host db_name"
  exit 1
fi

# Get SYS password
read -s -p "Enter SYS password for ${SCAN_HOST}/${DB_NAME}: " SYS_PASSWORD
echo

# HTML Header
cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
  <title>RAC Health Check: ${DB_NAME}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h2 { color: #2c3e50; border-bottom: 2px solid #3498db; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
    tr:hover { background-color: #f5f5f5; }
    .critical { color: #e74c3c; font-weight: bold; }
    .warning { color: #f39c12; }
    .ok { color: #27ae60; }
  </style>
</head>
<body>
  <h1>Oracle RAC Health Report: ${DB_NAME}</h1>
  <p>Generated at: $(date)</p>
  <p>SCAN Name: ${SCAN_HOST}</p>
EOF

# Function to run SQL and format as HTML table
run_sql_to_html() {
  local title="$1"
  local query="$2"
  local critical="$3"
  
  echo "<h2>${title}</h2>" >> "$REPORT_FILE"
  
  sqlplus -S "sys/${SYS_PASSWORD}@//${SCAN_HOST}:1521/${DB_NAME} as sysdba" << EOF | awk '
    BEGIN { print "<table>"; print "<tr><th>Metric</th><th>Value</th></tr>" }
    /^ERROR/ { print "<tr class=\"critical\"><td colspan=\"2\">" $0 "</td></tr>" }
    /=/ { 
      split($0, arr, "="); 
      cls = "";
      if (arr[2] ~ /CRITICAL/) cls = "critical";
      if (arr[2] ~ /WARNING/) cls = "warning";
      print "<tr><td>" arr[1] "</td><td class=\"" cls "\">" arr[2] "</td></tr>" 
    }
    END { print "</table>" }
  ' >> "$REPORT_FILE"
  
    SET FEEDBACK OFF HEADING OFF PAGESIZE 0 LINESIZE 1000
    ${query}
    EXIT
EOF
}

# RAC Node Status
run_sql_to_html "Cluster Node Status" "
  SELECT 'Node ' || instance_number || ': ' || 
         instance_name || ' (' || host_name || ')' || '=' ||
         status || ' | Version: ' || version || ' | Startup: ' || 
         TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI')
  FROM gv\$instance;
"

# Wait Events Analysis
run_sql_to_html "Top Wait Events (Non-Idle)" "
  SELECT event || '=' || 
         ROUND(time_waited_micro/1000000,1) || 's (Waits: ' || 
         total_waits || ', Avg: ' || 
         ROUND(time_waited_micro/total_waits/1000,2) || 'ms)'
  FROM (
    SELECT event, total_waits, time_waited_micro
    FROM gv\$system_event 
    WHERE wait_class NOT IN ('Idle', 'System I/O')
    ORDER BY time_waited_micro DESC
    FETCH FIRST 10 ROWS ONLY
  );
"

# Global Cache Statistics
run_sql_to_html "Global Cache Performance" "
  SELECT 
    'Global Cache CR Block Receive Time (ms)' || '=' ||
    ROUND((SUM(CASE name WHEN 'gc cr block receive time' THEN value END) /
           SUM(CASE name WHEN 'gc cr blocks received' THEN value END)) * 10,2)
    || 'ms [CR] | ' ||
    ROUND((SUM(CASE name WHEN 'gc current block receive time' THEN value END) /
           SUM(CASE name WHEN 'gc current blocks received' THEN value END)) * 10,2)
    || 'ms [Current]'
  FROM gv\$sysstat
  WHERE name IN (
    'gc cr block receive time', 'gc cr blocks received',
    'gc current block receive time', 'gc current blocks received'
  );
"

# Tablespace Usage
run_sql_to_html "Tablespace Usage" "
  SELECT tablespace_name || '=' || 
         ROUND(used_percent,1) || '% used | ' ||
         CASE WHEN used_percent > 90 THEN 'CRITICAL' 
              WHEN used_percent > 80 THEN 'WARNING' 
              ELSE 'OK' END
  FROM (
    SELECT a.tablespace_name, 
           (a.bytes_alloc - nvl(b.bytes_free,0))/a.bytes_alloc*100 used_percent
    FROM (
      SELECT tablespace_name, SUM(bytes) bytes_alloc
      FROM dba_data_files GROUP BY tablespace_name
    ) a,
    (
      SELECT tablespace_name, SUM(bytes) bytes_free
      FROM dba_free_space GROUP BY tablespace_name
    ) b
    WHERE a.tablespace_name = b.tablespace_name(+)
  )
  ORDER BY used_percent DESC;
"

# Cluster Interconnect
run_sql_to_html "Interconnect Health" "
  SELECT 
    'Network Latency (' || name || ')' || '=' ||
    ROUND(value/100,2) || 'ms' ||
    CASE WHEN value/100 > 2 THEN ' CRITICAL' 
         WHEN value/100 > 1 THEN ' WARNING' ELSE '' END
  FROM gv\$sysmetric 
  WHERE metric_name = 'Network Latency'
    AND group_id = 2
    AND value > 0;
"

# HTML Footer
cat >> "$REPORT_FILE" << EOF
</body>
</html>
EOF

echo -e "\nReport generated: ${REPORT_FILE}"

#!/bin/bash
# Oracle DB Health Check with HTML Email using mail command

# Configuration
DB_USER="sys as sysdba"
DB_PASS="your_password"
DB_SID="ORCL"
REPORT_FILE="/tmp/db_health_$(date +%Y%m%d).html"
EMAIL_TO="dba@company.com"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="DB Health Report - $(date +%F)"

# Function: Send HTML email using mail
send_email() {
    local report_file="$1"
    local subject="$2"
    local recipient="$3"
    local sender="$4"
    
    if ! command -v mail >/dev/null; then
        echo "Error: mail command not found!"
        return 1
    fi

    # Send email with HTML headers
    mail -s "$subject" -a "From: $sender" -a "Content-Type: text/html" "$recipient" < "$report_file"
    
    return $?
}

# Function: Run SQL and format as HTML table
run_sql_html() {
    local sql_query="$1"
    local section_title="$2"
    
    echo "<h2>$section_title</h2>" >> "$REPORT_FILE"
    
    sqlplus -S /nolog << EOF >> "$REPORT_FILE"
    connect $DB_USER/$DB_PASS@$DB_SID
    
    set markup html on table "class='sql-table'"
    set pagesize 500
    set linesize 200
    set feedback off
    set heading on
    
    $sql_query
    exit
EOF
}

# Generate HTML Report
{
echo "<html>
<head>
<title>Database Health Report</title>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  h1 { color: #2c3e50; }
  h2 { color: #3498db; border-bottom: 2px solid #3498db; }
  table { border-collapse: collapse; width: 100%; margin: 20px 0; }
  th { background-color: #3498db; color: white; padding: 10px; }
  td { padding: 8px; border: 1px solid #ddd; }
  tr:nth-child(even) { background-color: #f2f2f2; }
  .critical { color: #e74c3c; font-weight: bold; }
</style>
</head>
<body>
<h1>Database Health Report</h1>
<p>Generated: $(date)</p>"
} > "$REPORT_FILE"

# Run health checks
run_sql_html "SELECT name, open_mode, log_mode, created FROM v\$database;" "Database Status"
run_sql_html "SELECT inst_id, instance_name, status, host_name FROM gv\$instance;" "Instance Status"
run_sql_html "SELECT tablespace_name, 
    round(used_space/1024/1024) used_gb,
    round(tablespace_size/1024/1024) total_gb,
    round(used_percent) pct_used
    FROM dba_tablespace_usage_metrics
    ORDER BY pct_used DESC;" "Tablespace Usage"

run_sql_html "SELECT event, total_waits, 
    round(time_waited_micro/1000000) wait_sec
    FROM (
        SELECT event, total_waits, time_waited_micro
        FROM v\$system_event
        WHERE wait_class != 'Idle'
        ORDER BY time_waited_micro DESC
    ) WHERE rownum <= 5;" "Top 5 Wait Events"

echo "</body></html>" >> "$REPORT_FILE"

# Send email with error handling
if send_email "$REPORT_FILE" "$EMAIL_SUBJECT" "$EMAIL_TO" "$EMAIL_FROM"; then
    echo "Health report sent successfully to $EMAIL_TO"
else
    echo "Failed to send health report" >&2
    exit 1
fi

# Cleanup
rm -f "$REPORT_FILE"


send_email() {
  local host_entry="$1"
  local report_file="$2"

  local max_inline_size=2097152  # 2MB
  local file_size
  file_size=$(stat -c%s "$report_file")

  if [[ "$file_size" -le "$max_inline_size" ]]; then
    # Try sendmail first for inline HTML
    if command -v sendmail > /dev/null 2>&1; then
      {
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $EMAIL_SUBJECT - $host_entry"
        echo "Content-Type: text/html"
        echo
        cat "$report_file"
      } | sendmail -t
      log_msg "Email sent as inline HTML using sendmail for $host_entry"
    elif command -v mailx > /dev/null 2>&1; then
      mailx -a "Content-Type: text/html" -s "$EMAIL_SUBJECT - $host_entry" "$EMAIL_RECIPIENT" < "$report_file"
      log_msg "Email sent as inline HTML using mailx for $host_entry"
    else
      log_msg "ERROR: Neither sendmail nor mailx available for sending inline HTML email."
    fi
  else
    # Compress report and attach
    local zip_file="${report_file%.html}.zip"
    zip -j "$zip_file" "$report_file" > /dev/null

    if command -v sendmail > /dev/null 2>&1; then
      {
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $EMAIL_SUBJECT - $host_entry (Attached)"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary="MIXED-BOUNDARY""
        echo
        echo "--MIXED-BOUNDARY"
        echo "Content-Type: text/plain"
        echo
        echo "Health check report for $host_entry is attached (compressed)."
        echo
        echo "--MIXED-BOUNDARY"
        echo "Content-Type: application/zip; name="$(basename "$zip_file")""
        echo "Content-Disposition: attachment; filename="$(basename "$zip_file")""
        echo "Content-Transfer-Encoding: base64"
        echo
        base64 "$zip_file"
        echo "--MIXED-BOUNDARY--"
      } | sendmail -t
      log_msg "Email with ZIP attachment sent using sendmail for $host_entry"
    elif command -v mailx > /dev/null 2>&1; then
      echo "Health check report for $host_entry is attached (compressed)." | mailx -a "$zip_file" -s "$EMAIL_SUBJECT - $host_entry (Attached)" "$EMAIL_RECIPIENT"
      log_msg "Email with ZIP attachment sent using mailx for $host_entry"
    else
      log_msg "ERROR: Neither sendmail nor mailx available for sending ZIP attachment."
    fi
  fi
}
