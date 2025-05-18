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
