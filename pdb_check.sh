#!/bin/bash
# Oracle PDB Clone Precheck with Guaranteed Connection Resolution
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"
CONN_RETRIES=3
CONN_TIMEOUT=5

# Ensure TNS_ADMIN is set if tnsnames.ora exists in non-standard location
export TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"

# Helper functions
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

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

# Most reliable connection resolution method
resolve_connection() {
    local cdb=$(to_upper "$1")
    local host port
    
    # Method 1: Directly from tnsnames.ora (most reliable)
    if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
        local tns_entry=$(awk -v cdb="$cdb" '
            BEGIN {IGNORECASE=1; found=0}
            /^'"$cdb"'[[:space:]]*=/,/\)$/ {
                if ($0 ~ /HOST[[:space:]]*=/) {
                    gsub(/.*HOST[[:space:]]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]*\).*/, "")
                    host=$0
                }
                if ($0 ~ /PORT[[:space:]]*=/) {
                    gsub(/.*PORT[[:space:]]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]*\).*/, "")
                    port=$0
                }
                if ($0 ~ /\)$/) found=1
            }
            END {if (found && host && port) print host "|" port}
        ' "$TNS_ADMIN/tnsnames.ora")
        
        host=$(echo "$tns_entry" | cut -d'|' -f1)
        port=$(echo "$tns_entry" | cut -d'|' -f2)
    fi
    
    # Method 2: Try tnsping if tnsnames.ora method failed
    if [[ -z "$host" ]] && command -v tnsping >/dev/null; then
        local tnsping_output=$(timeout $CONN_TIMEOUT tnsping "$cdb" 2>&1)
        host=$(echo "$tnsping_output" | grep -A1 "HOST =" | tail -1 | awk '{print $1}' | tr -d '(),')
        port=$(echo "$tnsping_output" | grep "PORT =" | awk '{print $NF}' | tr -d '),')
    fi
    
    # Method 3: Hardcoded fallback (edit with your values)
    if [[ -z "$host" ]]; then
        case "$cdb" in
            "CDB1") host="oracle-host1.company.com"; port="1521" ;;
            "CDB2") host="oracle-host2.company.com"; port="1521" ;;
            "PRODDB") host="prod-db.company.com"; port="1522" ;;
            *) host=""; port="" ;;
        esac
    fi
    
    # Final validation
    if [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
        echo "SUCCESS|$host|$port"
    else
        echo "ERROR|Failed to resolve $cdb after all methods"
        return 1
    fi
}

# SQL execution with error handling
run_sql() {
    local conn_str="$1"
    local query="$2"
    local attempt=0
    
    while [ $attempt -lt $CONN_RETRIES ]; do
        result=$($SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off pagesize 0
connect $conn_str
$query
exit
EOF
        )
        
        if [ $? -eq 0 ]; then
            # Clean SQL*Plus output
            echo "$result" | sed '/^$/d' | head -1
            return 0
        fi
        
        ((attempt++))
        sleep 1
    done
    
    echo "ERROR|SQL execution failed after $CONN_RETRIES attempts"
    return 1
}

# Validation checks
check_pdb_exists() {
    local conn_str="$1"
    local pdb=$(to_upper "$2")
    
    result=$(run_sql "$conn_str" "
        SELECT name FROM v\\$pdbs WHERE UPPER(name) = '$pdb'")
    
    if [[ "$result" == "$pdb" ]]; then
        echo "PASS|PDB exists"
    else
        echo "FAIL|PDB not found"
    fi
}

check_local_undo() {
    local conn_str="$1"
    result=$(run_sql "$conn_str" "SELECT value FROM v\\$parameter WHERE name = 'local_undo_enabled'")
    
    if [[ "$result" == "TRUE" ]]; then
        echo "PASS|Local undo enabled"
    else
        echo "FAIL|Local undo not enabled (Value: ${result:-NOT_SET})"
    fi
}

check_tde_config() {
    local src_conn="$1" tgt_conn="$2"
    src_wallet=$(run_sql "$src_conn" "SELECT wallet_type FROM v\\$encryption_wallet")
    tgt_wallet=$(run_sql "$tgt_conn" "SELECT wallet_type FROM v\\$encryption_wallet")
    
    if [[ "$src_wallet" == "$tgt_wallet" ]]; then
        echo "PASS|TDE matches ($src_wallet)"
    else
        echo "FAIL|TDE mismatch (Source: $src_wallet, Target: $tgt_wallet)"
    fi
}

check_patch_level() {
    local src_conn="$1" tgt_conn="$2"
    src_patch=$(run_sql "$src_conn" "
        SELECT version || ':' || patch_id 
        FROM (SELECT version, patch_id FROM dba_registry_sqlpatch ORDER BY action_time DESC)
        WHERE ROWNUM = 1")
    tgt_patch=$(run_sql "$tgt_conn" "
        SELECT version || ':' || patch_id 
        FROM (SELECT version, patch_id FROM dba_registry_sqlpatch ORDER BY action_time DESC)
        WHERE ROWNUM = 1")
    
    if [[ "$src_patch" == "$tgt_patch" ]]; then
        echo "PASS|Patch levels match ($src_patch)"
    elif [[ -z "$src_patch" || -z "$tgt_patch" ]]; then
        echo "FAIL|Could not determine patch level (Source: $src_patch, Target: $tgt_patch)"
    else
        echo "FAIL|Patch level mismatch (Source: $src_patch, Target: $tgt_patch)"
    fi
}

check_db_components() {
    local src_conn="$1" tgt_conn="$2"
    src_comps=$(run_sql "$src_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry")
    tgt_comps=$(run_sql "$tgt_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry")
    
    if [[ "$src_comps" == "$tgt_comps" ]]; then
        echo "PASS|Components match"
    else
        echo "FAIL|Components differ (Source: $src_comps, Target: $tgt_comps)"
    fi
}

# Main validation function
validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    
    echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
    
    # Resolve source connection
    src_info=$(resolve_connection "$src_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ src_host src_port <<< "$src_info"
    src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection
    tgt_info=$(resolve_connection "$tgt_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${tgt_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ tgt_host tgt_port <<< "$tgt_info"
    tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
    
    # Perform checks
    checks=(
        "PDB Existence" "$(check_pdb_exists "$src_conn" "$pdb")"
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Config" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
    )
    
    # Generate report rows
    for ((i=0; i<${#checks[@]}; i+=2)); do
        IFS='|' read -r status details <<< "${checks[i+1]}"
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "${checks[i]}" "${status:-ERROR}" "${details:-Check failed}" ""
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

# Email handling
if [ -n "$EMAIL_TO" ]; then
    if mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"; then
        echo "Report sent to $EMAIL_TO"
    else
        echo "Failed to send email report"
    fi
fi

echo "Report generated: $HTML_FILE"

#!/bin/bash
# Oracle PDB Clone Precheck with Guaranteed Connection Resolution
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"
CONN_RETRIES=3
CONN_TIMEOUT=5

# Ensure TNS_ADMIN is set if tnsnames.ora exists in non-standard location
export TNS_ADMIN="${TNS_ADMIN:-$ORACLE_HOME/network/admin}"

# Helper functions
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

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

# Most reliable connection resolution method
resolve_connection() {
    local cdb=$(to_upper "$1")
    local host port
    
    # Method 1: Directly from tnsnames.ora (most reliable)
    if [ -f "$TNS_ADMIN/tnsnames.ora" ]; then
        local tns_entry=$(awk -v cdb="$cdb" '
            BEGIN {IGNORECASE=1; found=0}
            /^'"$cdb"'[[:space:]]*=/,/\)$/ {
                if ($0 ~ /HOST[[:space:]]*=/) {
                    gsub(/.*HOST[[:space:]]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]*\).*/, "")
                    host=$0
                }
                if ($0 ~ /PORT[[:space:]]*=/) {
                    gsub(/.*PORT[[:space:]]*=[[:space:]]*/, "")
                    gsub(/[[:space:]]*\).*/, "")
                    port=$0
                }
                if ($0 ~ /\)$/) found=1
            }
            END {if (found && host && port) print host "|" port}
        ' "$TNS_ADMIN/tnsnames.ora")
        
        host=$(echo "$tns_entry" | cut -d'|' -f1)
        port=$(echo "$tns_entry" | cut -d'|' -f2)
    fi
    
    # Method 2: Try tnsping if tnsnames.ora method failed
    if [[ -z "$host" ]] && command -v tnsping >/dev/null; then
        local tnsping_output=$(timeout $CONN_TIMEOUT tnsping "$cdb" 2>&1)
        host=$(echo "$tnsping_output" | grep -A1 "HOST =" | tail -1 | awk '{print $1}' | tr -d '(),')
        port=$(echo "$tnsping_output" | grep "PORT =" | awk '{print $NF}' | tr -d '),')
    fi
    
    # Method 3: Hardcoded fallback (edit with your values)
    if [[ -z "$host" ]]; then
        case "$cdb" in
            "CDB1") host="oracle-host1.company.com"; port="1521" ;;
            "CDB2") host="oracle-host2.company.com"; port="1521" ;;
            "PRODDB") host="prod-db.company.com"; port="1522" ;;
            *) host=""; port="" ;;
        esac
    fi
    
    # Final validation
    if [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
        echo "SUCCESS|$host|$port"
    else
        echo "ERROR|Failed to resolve $cdb after all methods"
        return 1
    fi
}

# SQL execution with error handling
run_sql() {
    local conn_str="$1"
    local query="$2"
    local attempt=0
    
    while [ $attempt -lt $CONN_RETRIES ]; do
        result=$($SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off pagesize 0
connect $conn_str
$query
exit
EOF
        )
        
        if [ $? -eq 0 ]; then
            # Clean SQL*Plus output
            echo "$result" | sed '/^$/d' | head -1
            return 0
        fi
        
        ((attempt++))
        sleep 1
    done
    
    echo "ERROR|SQL execution failed after $CONN_RETRIES attempts"
    return 1
}

# Validation checks
check_pdb_exists() {
    local conn_str="$1"
    local pdb=$(to_upper "$2")
    
    result=$(run_sql "$conn_str" "
        SELECT name FROM v\\$pdbs WHERE UPPER(name) = '$pdb'")
    
    if [[ "$result" == "$pdb" ]]; then
        echo "PASS|PDB exists"
    else
        echo "FAIL|PDB not found"
    fi
}

check_local_undo() {
    local conn_str="$1"
    result=$(run_sql "$conn_str" "SELECT value FROM v\\$parameter WHERE name = 'local_undo_enabled'")
    
    if [[ "$result" == "TRUE" ]]; then
        echo "PASS|Local undo enabled"
    else
        echo "FAIL|Local undo not enabled (Value: ${result:-NOT_SET})"
    fi
}

check_tde_config() {
    local src_conn="$1" tgt_conn="$2"
    src_wallet=$(run_sql "$src_conn" "SELECT wallet_type FROM v\\$encryption_wallet")
    tgt_wallet=$(run_sql "$tgt_conn" "SELECT wallet_type FROM v\\$encryption_wallet")
    
    if [[ "$src_wallet" == "$tgt_wallet" ]]; then
        echo "PASS|TDE matches ($src_wallet)"
    else
        echo "FAIL|TDE mismatch (Source: $src_wallet, Target: $tgt_wallet)"
    fi
}

check_patch_level() {
    local src_conn="$1" tgt_conn="$2"
    src_patch=$(run_sql "$src_conn" "
        SELECT version || ':' || patch_id 
        FROM (SELECT version, patch_id FROM dba_registry_sqlpatch ORDER BY action_time DESC)
        WHERE ROWNUM = 1")
    tgt_patch=$(run_sql "$tgt_conn" "
        SELECT version || ':' || patch_id 
        FROM (SELECT version, patch_id FROM dba_registry_sqlpatch ORDER BY action_time DESC)
        WHERE ROWNUM = 1")
    
    if [[ "$src_patch" == "$tgt_patch" ]]; then
        echo "PASS|Patch levels match ($src_patch)"
    elif [[ -z "$src_patch" || -z "$tgt_patch" ]]; then
        echo "FAIL|Could not determine patch level (Source: $src_patch, Target: $tgt_patch)"
    else
        echo "FAIL|Patch level mismatch (Source: $src_patch, Target: $tgt_patch)"
    fi
}

check_db_components() {
    local src_conn="$1" tgt_conn="$2"
    src_comps=$(run_sql "$src_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry")
    tgt_comps=$(run_sql "$tgt_conn" "
        SELECT LISTAGG(comp_name, ', ') WITHIN GROUP (ORDER BY comp_name) 
        FROM dba_registry")
    
    if [[ "$src_comps" == "$tgt_comps" ]]; then
        echo "PASS|Components match"
    else
        echo "FAIL|Components differ (Source: $src_comps, Target: $tgt_comps)"
    fi
}

# Main validation function
validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    
    echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
    
    # Resolve source connection
    src_info=$(resolve_connection "$src_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ src_host src_port <<< "$src_info"
    src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection
    tgt_info=$(resolve_connection "$tgt_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${tgt_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ tgt_host tgt_port <<< "$tgt_info"
    tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
    
    # Perform checks
    checks=(
        "PDB Existence" "$(check_pdb_exists "$src_conn" "$pdb")"
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Config" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
    )
    
    # Generate report rows
    for ((i=0; i<${#checks[@]}; i+=2)); do
        IFS='|' read -r status details <<< "${checks[i+1]}"
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "${checks[i]}" "${status:-ERROR}" "${details:-Check failed}" ""
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

# Email handling
if [ -n "$EMAIL_TO" ]; then
    if mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"; then
        echo "Report sent to $EMAIL_TO"
    else
        echo "Failed to send email report"
    fi
fi

echo "Report generated: $HTML_FILE"

#!/bin/bash
# Oracle PDB Clone Precheck with Enhanced Connection Handling
# Usage: ./pdb_precheck.sh <input_file.txt> [email@domain.com]

# Configuration
SQLPLUS="/u01/app/oracle/product/19c/dbhome_1/bin/sqlplus -s"
REPORT_DIR="./reports"
HTML_FILE="$REPORT_DIR/pdb_precheck_$(date +%Y%m%d_%H%M%S).html"
EMAIL_TO="${2:-}"
EMAIL_FROM="dba@company.com"
EMAIL_SUBJECT="PDB Clone Precheck Report"
CONN_RETRIES=3
CONN_TIMEOUT=5

# Portable uppercase conversion
to_upper() {
    echo "$1" | awk '{print toupper($0)}'
}

# Try multiple connection methods
resolve_connection() {
    local cdb=$(to_upper "$1")
    local host port
    
    # Method 1: Try tnsping first
    if command -v tnsping >/dev/null; then
        local tnsping_output=$(timeout $CONN_TIMEOUT tnsping "$cdb" 2>/dev/null)
        host=$(echo "$tnsping_output" | awk '/HOST = / {for(i=1;i<=NF;i++) if ($i=="HOST") {print $(i+2)}; exit}' | tr -d ')(,')
        port=$(echo "$tnsping_output" | awk '/PORT = / {for(i=1;i<=NF;i++) if ($i=="PORT") {print $(i+2)}; exit}' | tr -d ')(,')
    fi
    
    # Method 2: Try tnsnames.ora lookup (if file exists)
    if [[ -z "$host" && -f "$TNS_ADMIN/tnsnames.ora" ]]; then
        local tns_entry=$(awk -v cdb="$cdb" 'BEGIN{IGNORECASE=1} $0 ~ cdb {p=1} p && /HOST *=/ {print; exit}' "$TNS_ADMIN/tnsnames.ora")
        host=$(echo "$tns_entry" | awk -F'=' '{print $2}' | tr -d ' )(,' | cut -d'.' -f1)
        port=$(echo "$tns_entry" | awk -F'PORT *= *' '{print $2}' | tr -d ' )(,')
    fi
    
    # Method 3: Try default ports if CDB is known
    if [[ -z "$host" ]]; then
        case "$cdb" in
            "CDB1") host="oracle-host1"; port="1521" ;;
            "CDB2") host="oracle-host2"; port="1521" ;;
            # Add more default mappings as needed
        esac
    fi
    
    # Final validation
    if [[ -n "$host" && -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
        echo "SUCCESS|$host|$port"
    else
        echo "ERROR|Failed to resolve $cdb (Tried tnsping, tnsnames.ora, and default mappings)"
        return 1
    fi
}

# SQL execution with retries
run_sql() {
    local conn_str="$1"
    local query="$2"
    local attempt=0
    
    while [ $attempt -lt $CONN_RETRIES ]; do
        result=$($SQLPLUS -S "/ as sysdba" <<EOF
whenever sqlerror exit failure
set heading off feedback off verify off
connect $conn_str
$query
exit
EOF
        )
        
        [ $? -eq 0 ] && echo "$result" && return 0
        ((attempt++))
        sleep 1
    done
    
    echo "ERROR|SQL execution failed after $CONN_RETRIES attempts"
    return 1
}

# Main validation function
validate_pdb_pair() {
    local src_cdb=$(to_upper "$1")
    local tgt_cdb=$(to_upper "$2")
    local pdb=$(to_upper "$3")
    
    # Resolve source connection
    src_info=$(resolve_connection "$src_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${src_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ src_host src_port <<< "$src_info"
    src_conn="/@//${src_host}:${src_port}/${src_cdb} as sysdba"
    
    # Resolve target connection
    tgt_info=$(resolve_connection "$tgt_cdb") || {
        html_add_row "$src_cdb" "$tgt_cdb" "$pdb" "Connection" "fail" "${tgt_info#*|}" ""
        return 1
    }
    IFS='|' read -r _ tgt_host tgt_port <<< "$tgt_info"
    tgt_conn="/@//${tgt_host}:${tgt_port}/${tgt_cdb} as sysdba"
    
    # Perform checks
    checks=(
        "PDB Existence" "$(check_pdb_exists "$src_conn" "$pdb")"
        "Local Undo" "$(check_local_undo "$src_conn")"
        "TDE Config" "$(check_tde_config "$src_conn" "$tgt_conn")"
        "Patch Level" "$(check_patch_level "$src_conn" "$tgt_conn")"
        "DB Components" "$(check_db_components "$src_conn" "$tgt_conn")"
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
    echo "Processing: $src_cdb => $tgt_cdb (PDB: $pdb)"
    validate_pdb_pair "$src_cdb" "$tgt_cdb" "$pdb"
done < "$1"

html_footer

# Email handling
[ -n "$EMAIL_TO" ] && mailx -s "$EMAIL_SUBJECT" -a "Content-Type: text/html" -r "$EMAIL_FROM" "$EMAIL_TO" < "$HTML_FILE"

echo "Report generated: $HTML_FILE"
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
