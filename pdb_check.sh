#!/bin/bash
# Oracle PDB Clone Precheck Script with Comprehensive Checks
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
run_sql() {
    local conn_str="$1"
    local query="$2"
    $SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off
connect $conn_str
$query
exit
EOF
}

check_local_undo() {
    local conn_str="$1"
    local result=$(run_sql "$conn_str" "SELECT value FROM v\$parameter WHERE name = 'local_undo_enabled';")
    if [ "$result" != "TRUE" ]; then
        echo "FAIL|Local undo not enabled"
    else
        echo "PASS|Local undo enabled"
    fi
}

check_tde_config() {
    local src_conn="$1" tgt_conn="$2"
    local src_wallet=$(run_sql "$src_conn" "SELECT wallet_type FROM v\$encryption_wallet;")
    local tgt_wallet=$(run_sql "$tgt_conn" "SELECT wallet_type FROM v\$encryption_wallet;")
    
    if [ "$src_wallet" != "$tgt_wallet" ]; then
        echo "FAIL|TDE mismatch (Source: $src_wallet, Target: $tgt_wallet)"
    else
        echo "PASS|TDE configuration matches ($src_wallet)"
    fi
}

check_patch_level() {
    local src_conn="$1" tgt_conn="$2"
    local src_patch=$(run_sql "$src_conn" "
        SELECT TO_CHAR(MAX(action_time), MAX(version), MAX(patch_id) 
        FROM dba_registry_sqlpatch;")
    
    local tgt_patch=$(run_sql "$tgt_conn" "
        SELECT TO_CHAR(MAX(action_time)), MAX(version), MAX(patch_id) 
        FROM dba_registry_sqlpatch;")
    
    if [[ "$src_patch" > "$tgt_patch" ]]; then
        echo "FAIL|Target patch level lower than source (Source: $src_patch, Target: $tgt_patch)"
    else
        echo "PASS|Patch level compatible (Source: $src_patch, Target: $tgt_patch)"
    fi
}

check_db_components() {
    local src_conn="$1" tgt_conn="$2"
    local src_comps=$(run_sql "$src_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry;")
    
    local tgt_comps=$(run_sql "$tgt_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry;")
    
    if [ "$src_comps" != "$tgt_comps" ]; then
        echo "FAIL|Components differ (Source: $src_comps, Target: $tgt_comps)"
    else
        echo "PASS|All components match ($src_comps)"
    fi
}

# Main validation function
validate_pdb_pair() {
    local src_cdb="$1" tgt_cdb="$2" pdb="$3"
    
    # Resolve source connection
    local src_info=$(get_db_connection "$src_cdb")
    if [[ "$src_info" == ERROR* ]]; then
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    fi
    local src_host=$(echo "$src_info" | cut -d'|' -f2)
    local src_port=$(echo "$src_info" | cut -d'|' -f3)
    local src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection
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

# Main execution
[ $# -lt 1 ] && echo "Usage: $0 <input_file.txt> [email]" && exit 1

mkdir -p "$REPORT_DIR"
html_header

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
