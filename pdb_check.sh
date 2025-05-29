#!/bin/bash
# Oracle PDB Clone Precheck Script with Automatic Host Discovery
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
TNSPING="$ORACLE_HOME/bin/tnsping"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"

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
EOF
}

html_add_row() {
    echo "<tr><td>$1</td><td>$2</td><td>$3</td><td class=\"$4\">$5</td><td>$6</td></tr>" >> "$HTML_FILE"
}

html_footer() {
    echo "</table></body></html>" >> "$HTML_FILE"
}

# Get connection details via tnsping
get_db_connection() {
    local container=$1
    local result=$($TNSPING $container 2>/dev/null | grep "HOST\|PORT")
    
    if [ -z "$result" ]; then
        echo "ERROR|Failed to resolve $container"
        return 1
    fi
    
    local host=$(echo "$result" | grep HOST | head -1 | awk -F'=' '{print $2}' | awk '{print $1}' | tr -d ')')
    local port=$(echo "$result" | grep PORT | head -1 | awk -F'=' '{print $2}' | awk '{print $1}' | tr -d ')')
    
    echo "SUCCESS|$host|$port"
}

# Database validation functions
check_pdb_status() {
    local conn_str="$1" pdb="$2"
    $SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect $conn_str
SELECT open_mode FROM v\$pdbs WHERE name = '$pdb';
exit
EOF
}

check_max_string_size() {
    local conn_str="$1"
    $SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
connect $conn_str
SELECT value FROM v\$parameter WHERE name = 'max_string_size';
exit
EOF
}

# Main validation function
validate_pdb_pair() {
    local src_cdb="$1" tgt_cdb="$2" pdb="$3"
    
    # Resolve source connection
    local src_info=$(get_db_connection "$src_cdb")
    if [[ "$src_info" == ERROR* ]]; then
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "fail" "Connection Failed" "${src_info#*|}"
        return 1
    fi
    local src_host=$(echo "$src_info" | cut -d'|' -f2)
    local src_port=$(echo "$src_info" | cut -d'|' -f3)
    local src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection
    local tgt_info=$(get_db_connection "$tgt_cdb")
    if [[ "$tgt_info" == ERROR* ]]; then
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "fail" "Connection Failed" "${tgt_info#*|}"
        return 1
    fi
    local tgt_host=$(echo "$tgt_info" | cut -d'|' -f2)
    local tgt_port=$(echo "$tgt_info" | cut -d'|' -f3)
    local tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
    
    # Start validation
    local status="pass"
    local details=""
    local errors=""
    
    # 1. Check PDB exists in source
    if ! check_pdb_status "$src_conn" "$pdb" >/dev/null; then
        errors+="Source PDB $pdb not found. "
        status="fail"
    fi
    
    # 2. Check PDB doesn't exist in target
    if check_pdb_status "$tgt_conn" "$pdb" >/dev/null; then
        errors+="Target PDB $pdb already exists. "
        status="fail"
    fi
    
    # 3. Compare MAX_STRING_SIZE
    local src_size=$(check_max_string_size "$src_conn")
    local tgt_size=$(check_max_string_size "$tgt_conn")
    if [ "$src_size" != "$tgt_size" ]; then
        errors+="MAX_STRING_SIZE mismatch (Source: $src_size, Target: $tgt_size). "
        status="fail"
    fi
    
    # Add results to report
    html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "$status" "$([ -z "$errors" ] && echo "All checks passed" || echo "$errors")" \
                "Source: ${src_host}:${src_port}<br>Target: ${tgt_host}:${tgt_port}"
    
    return $([ "$status" == "pass" ] && echo 0 || echo 1)
}

# Main execution
[ $# -lt 1 ] && echo "Usage: $0 <input_file.txt> [email]" && exit 1

mkdir -p "$REPORT_DIR"
html_header
echo "<table><tr><th>Source CDB</th><th>Target CDB</th><th>PDB</th><th>Status</th><th>Details</th><th>Connection Info</th></tr>" >> "$HTML_FILE"

while IFS="|" read -r src_cdb tgt_cdb pdb; do
    # Skip comments and empty lines
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    
    validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"
done < "$1"

html_footer

# Email report if address provided
if [ -n "$EMAIL_TO" ]; then
    mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"
fi

echo "Report generated: $HTML_FILE"
