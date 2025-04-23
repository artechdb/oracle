#!/bin/bash

# Variables (update as needed)
SYS_USER="sys"
SYS_PASSWORD="your_password"
EMAIL_RECIPIENT="you@example.com"
INPUT_FILE="db_targets.txt"
SQL_SCRIPT="db_healthcheck_clean.sql"
LOG_DIR="./healthcheck_logs"
EMAIL_SUBJECT="Oracle DB Health Check Report"
LOG_FILE="$LOG_DIR/healthcheck_run.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to log messages with timestamp
log_msg() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $msg" | tee -a "$LOG_FILE"
}

# Function to extract DB info
get_db_info() {
  log_msg "Reading DB targets from $INPUT_FILE"
  if [[ ! -f "$INPUT_FILE" ]]; then
    log_msg "ERROR: Input file $INPUT_FILE not found."
    exit 1
  fi

  mapfile -t DB_LIST < <(grep -v '^#' "$INPUT_FILE" | tr -d '[:space:]' | grep -v '^$')

  if [[ ${#DB_LIST[@]} -eq 0 ]]; then
    log_msg "ERROR: No valid DB entries found in $INPUT_FILE"
    exit 1
  fi
}

# Function to run health check for a DB
db_health_check() {
  local host_entry="$1"
  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  local report_file="$LOG_DIR/healthcheck_$(echo "$host_entry" | tr '/:' '_')_${timestamp}.html"

  log_msg "Running health check for $host_entry"
  
  sqlplus -s "$SYS_USER/$SYS_PASSWORD@$host_entry as sysdba" @"$SQL_SCRIPT" |   awk 'BEGIN { print "<pre style=\"font-family: monospace\">" } { print } END { print "</pre>" }' > "$report_file"

  if [[ ! -s "$report_file" ]]; then
    log_msg "WARNING: Empty or failed report for $host_entry"
  else
    log_msg "Health check report saved to $report_file"
  fi

  echo "$report_file"
}

# Function to send HTML email, fallback to mailx if sendmail not present
send_email() {
  local host_entry="$1"
  local report_file="$2"

  if command -v sendmail > /dev/null 2>&1; then
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $EMAIL_SUBJECT - $host_entry"
      echo "Content-Type: text/html"
      echo
      cat "$report_file"
    } | sendmail -t
    log_msg "Email sent via sendmail for $host_entry"
  elif command -v mailx > /dev/null 2>&1; then
    mailx -a "Content-Type: text/html" -s "$EMAIL_SUBJECT - $host_entry" "$EMAIL_RECIPIENT" < "$report_file"
    log_msg "Email sent via mailx for $host_entry"
  else
    log_msg "ERROR: No supported mail client (sendmail or mailx) found."
  fi
}

# Main driver function
main() {
  get_db_info

  for host_entry in "${DB_LIST[@]}"; do
    log_msg "Processing target: $host_entry"
    report_file=$(db_health_check "$host_entry")
    send_email "$host_entry" "$report_file"
  done

  log_msg "Health check run complete for all targets."
}

# Execute main
main
