#!/bin/bash
# Oracle PDB Clone Precheck Script with Robust Host/Port Extraction
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
TNSPING="$ORACLE_HOME/bin/tnsping"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"
FAILED_CONNECTIONS=0

# Initialize HTML Report
html_header() {
    cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; margin: 20px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
  th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
  th { background-color: #f2f2f2; }
  .pass { background-color: #dfffdf; }
  .fail { background-color: #ffe8e8; }
  .warning { background-color: #fff3e0; }
  a { color: #0066cc; text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
<title>PDB Clone Precheck Report</title>
</head>
<body>
<h1>Oracle PDB Clone Precheck Report</h1>
<p>Generated: $(date)</p>
<table>
<tr>
  <th>Source CDB</th>
  <th>Target CDB</th>
  <th>PDB</th>
  <th>Check</th>
  <th>Status</th>
  <th>Details</th>
</tr>
EOF
}

html_add_row() {
    echo "<tr>
      <td>$1</td>
      <td>$2</td>
      <td>$3</td>
      <td>$4</td>
      <td class=\"$5\">$6</td>
      <td>$7</td>
    </tr>" >> "$HTML_FILE"
}

html_footer() {
    echo "</table>" >> "$HTML_FILE"
    if [ $FAILED_CONNECTIONS -gt 0 ]; then
        echo "<div class='fail'>Warning: $FAILED_CONNECTIONS database connections failed</div>" >> "$HTML_FILE"
    fi
    echo "</body></html>" >> "$HTML_FILE"
}

# Improved host/port extraction with error handling
get_db_connection() {
    local container=$1
    local attempts=0
    local max_attempts=3
    local result=""
    
    while [ $attempts -lt $max_attempts ]; do
        result=$($TNSPING $container 2>&1)
        
        # Extract host (handles multiple formats)
        local host=$(echo "$result" | grep -Po "(?<=HOST\s?=\s?)[^)]+" | head -1 | awk '{print $1}' | tr -d ' ')
        
        # Extract port (more robust parsing)
        local port=$(echo "$result" | grep -Po "(?<=PORT\s?=\s?)[^)]+" | head -1 | awk '{print $1}' | tr -d ' ')
        
        # Validate extracted values
        if [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
            echo "SUCCESS|$host|$port"
            return 0
        fi
        
        ((attempts++))
        sleep 1
    done
    
    echo "ERROR|Failed to resolve connection details for $container after $max_attempts attempts"
    ((FAILED_CONNECTIONS++))
    return 1
}

# Database validation functions (keep existing implementations)
run_sql() {
    local conn_str="$1"
    local query="$2"
    local max_attempts=2
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        result=$($SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off
connect $conn_str
$query
exit
EOF
        )
        
        if [ $? -eq 0 ]; then
            echo "$result"
            return 0
        fi
        
        ((attempts++))
        sleep 1
    done
    
    echo "ERROR|SQL execution failed"
    return 1
}

check_local_undo() {
    local conn_str="$1"
    local result=$(run_sql "$conn_str" "SELECT value FROM v\$parameter WHERE name = 'local_undo_enabled';")
    
    if [[ "$result" == "ERROR"* ]]; then
        echo "FAIL|Connection failed"
    elif [ "$result" != "TRUE" ]; then
        echo "FAIL|Local undo not enabled"
    else
        echo "PASS|Local undo enabled"
    fi
}

# Main validation function with enhanced error handling
validate_pdb_pair() {
    local src_cdb="$1" tgt_cdb="$2" pdb="$3"
    
    # Resolve source connection with retries
    local src_info=$(get_db_connection "$src_cdb")
    if [[ "$src_info" == ERROR* ]]; then
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    fi
    local src_host=$(echo "$src_info" | cut -d'|' -f2)
    local src_port=$(echo "$src_info" | cut -d'|' -f3)
    local src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection with retries
    local tgt_info=$(get_db_connection "$tgt_cdb")
    if [[ "$tgt_info" == ERROR* ]]; then
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${tgt_info#*|}" ""
        return 1
    fi
    local tgt_host=$(echo "$tgt_info" | cut -d'|' -f2)
    local tgt_port=$(echo "$tgt_info" | cut -d'|' -f3)
    local tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
    
    # Perform all checks
    local checks=(
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Config" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
    )
    
    # Process check results
    for ((i=0; i<${#checks[@]}; i+=2)); do
        local check_name="${checks[i]}"
        IFS='|' read -r status details <<< "${checks[i+1]}"
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "$check_name" "$status" "$details" ""
    done
}

# Main execution with proper error handling
[ $# -lt 1 ] && echo "Usage: $0 <input_file.txt> [email]" && exit 1

mkdir -p "$REPORT_DIR"
html_header

while IFS="|" read -r src_cdb tgt_cdb pdb; do
    # Skip comments and empty lines
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    
    echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
    validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"
done < "$1"

html_footer

# Email report if address provided
if [ -n "$EMAIL_TO" ]; then
    if mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"; then
        echo "Report sent to $EMAIL_TO"
    else
        echo "Failed to send email report"
    fi
fi

echo "Report generated: $HTML_FILE"
exit $((FAILED_CONNECTIONS > 0 ? 1 : 0))
