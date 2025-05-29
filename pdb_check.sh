#!/bin/bash
# Oracle PDB Clone Precheck with Uppercase Consistency
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
TNSPING="$ORACLE_HOME/bin/tnsping"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"

# Function to convert to uppercase
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Initialize HTML Report
html_header() {
    cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
<style>
  /* ... (keep existing styles) ... */
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

# Database validation with uppercase consistency
check_pdb_exists() {
    local conn_str="$1"
    local pdb="$2"
    local pdb_upper=$(to_upper "$pdb")
    
    result=$(run_sql "$conn_str" "
        SELECT UPPER(name) FROM v\\$pdbs 
        WHERE UPPER(name) = '$pdb_upper'")
    
    if [ -z "$result" ]; then
        echo "FAIL|PDB $pdb_upper not found"
    else
        echo "PASS|PDB $pdb_upper exists"
    fi
}

check_max_string_size() {
    local src_conn="$1" tgt_conn="$2"
    
    src_size=$(run_sql "$src_conn" "
        SELECT UPPER(NVL(
            (SELECT value FROM v\\$parameter WHERE UPPER(name) = 'MAX_STRING_SIZE'),
            'STANDARD'
        )) FROM dual")

    tgt_size=$(run_sql "$tgt_conn" "
        SELECT UPPER(NVL(
            (SELECT value FROM v\\$parameter WHERE UPPER(name) = 'MAX_STRING_SIZE'),
            'STANDARD'
        )) FROM dual")

    if [ "$src_size" != "$tgt_size" ]; then
        echo "FAIL|MAX_STRING_SIZE mismatch (Source: $src_size, Target: $tgt_size)"
    else
        echo "PASS|MAX_STRING_SIZE matches ($src_size)"
    fi
}

# Main validation function with uppercase enforcement
validate_pdb_pair() {
    # Convert all input to uppercase
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    
    # Resolve connections (existing implementation)
    # ...
    
    # Perform checks with uppercase consistency
    checks=(
        "PDB Existence" "$(check_pdb_exists "$src_conn" "$pdb")"
        "MAX_STRING_SIZE" "$(check_max_string_size "$src_conn" "$tgt_conn")"
        # ... other checks ...
    )
    
    # Process results
    for ((i=0; i<${#checks[@]}; i+=2)); do
        IFS='|' read -r status details <<< "${checks[i+1]}"
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "${checks[i]}" "$status" "$details"
    done
}

# Main execution
while IFS="|" read -r src_cdb tgt_cdb pdb; do
    [[ "$src_cdb" =~ ^# ]] && continue
    
    # Process with uppercase conversion
    validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"
done < "$1"
