#!/bin/bash
# Oracle PDB Clone Precheck with Portable Host/Port Extraction
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
TNSPING="$ORACLE_HOME/bin/tnsping"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"

# Portable uppercase conversion
to_upper() {
    echo "$1" | awk '{print toupper($0)}'
}

# Robust host/port extraction without lookbehind
get_db_connection() {
    local container=$1
    local result=$($TNSPING $container 2>&1)
    
    # Extract host (portable method)
    local host=$(echo "$result" | awk '/HOST = / {for(i=1;i<=NF;i++) if ($i=="HOST") {print $(i+2)}; exit}' | tr -d ')(,')
    
    # Extract port (portable method)
    local port=$(echo "$result" | awk '/PORT = / {for(i=1;i<=NF;i++) if ($i=="PORT") {print $(i+2)}; exit}' | tr -d ')(,')
    
    # Validate extracted values
    if [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
        echo "SUCCESS|$(to_upper "$host")|$port"
    else
        echo "ERROR|Failed to resolve $container (Host: '$host', Port: '$port')"
        return 1
    fi
}

# SQL execution with uppercase conversion
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

# Uppercase comparison for PDB existence
check_pdb_exists() {
    local conn_str="$1"
    local pdb_upper=$(to_upper "$2")
    
    result=$(run_sql "$conn_str" "
        SELECT name FROM v\\$pdbs 
        WHERE UPPER(name) = '$pdb_upper'")
    
    if [ -z "$result" ]; then
        echo "FAIL|PDB $pdb_upper not found"
    else
        echo "PASS|PDB $pdb_upper exists"
    fi
}

# Uppercase comparison for parameters
check_parameter() {
    local conn_str="$1"
    local param_name=$(to_upper "$2")
    
    result=$(run_sql "$conn_str" "
        SELECT UPPER(value) FROM v\\$parameter 
        WHERE UPPER(name) = '$param_name'")
    
    echo "${result:-NOT_SET}"
}

# Main validation
validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    
    # Resolve connections
    src_info=$(get_db_connection "$src_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    }
    tgt_info=$(get_db_connection "$tgt_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${tgt_info#*|}" ""
        return 1
    }
    
    # Process checks
    checks=(
        "PDB Existence" "$(check_pdb_exists "/@//${src_info#*|}/$src_cdb as sysdba" "$pdb")"
        "MAX_STRING_SIZE" "$(compare_values "$src_cdb" "$tgt_cdb" "max_string_size")"
        # Add other checks here
    )
    
    # Generate report rows
    for ((i=0; i<${#checks[@]}; i+=2)); do
        IFS='|' read -r status details <<< "${checks[i+1]}"
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "${checks[i]}" "${status:-ERROR}" "${details:-Check failed}"
    done
}

# Main execution
[ $# -lt 1 ] && { echo "Usage: $0 <input_file.txt> [email]"; exit 1; }

mkdir -p "$REPORT_DIR"
html_header

while IFS="|" read -r src_cdb tgt_cdb pdb; do
    [[ "$src_cdb" =~ ^# || -z "$src_cdb" ]] && continue
    validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"
done < "$1"

html_footer

# Email handling (if configured)
[ -n "$EMAIL_TO" ] && mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"

echo "Report generated: $HTML_FILE"

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
