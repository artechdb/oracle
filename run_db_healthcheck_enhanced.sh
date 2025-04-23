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
