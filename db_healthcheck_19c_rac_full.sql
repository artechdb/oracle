#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}  # Fallback to 1521 if not specified

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Split into main config and optional port override
  IFS=':' read -r main_config port_override <<< "$line"
  
  # Parse main configuration (pipe-delimited)
  IFS='|' read -r SOURCE_CDB SOURCE_PDB SOURCE_SCAN TARGET_CDB TARGET_PDB TARGET_SCAN <<< "$main_config"
  
  # Use override port if specified, else default
  PORT=${port_override:-$DEFAULT_PORT}

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB} (Port: $PORT)"
  
  # Verify connections
  verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" || continue
  verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" || continue

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!" >&2
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Validate and parse the configuration line
  if ! validate_and_parse_line "$line"; then
    echo "Skipping invalid line: $line" >&2
    continue
  fi

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify connections
  if ! verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "COMPLETED"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

exit 0

pdb_compatibility_functions.sh
  #!/bin/bash

# Function to check PDB existence
check_pdb_existence() {
  local conn_str=$1
  local pdb_name=$2
  local type=$3
  local report_file=$4

  echo "<div class='section'>" >> "$report_file"
  echo "<h2>PDB Existence Check: $type</h2>" >> "$report_file"

  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'EXISTS' FROM v\$pdbs WHERE name = UPPER('$pdb_name');
EOF
  )

  if [[ "$result" == *"EXISTS"* ]]; then
    pdb_status=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Status: ' || open_mode || ' | Restricted: ' || restricted || 
       ' | Recovery: ' || recovery_status || ' | Con_ID: ' || con_id
FROM v\$pdbs WHERE name = UPPER('$pdb_name');
EOF
    )
    echo "<p class='ok'>✅ PDB $pdb_name exists</p>" >> "$report_file"
    echo "<p>PDB details: $pdb_status</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 0
  else
    echo "<p class='critical'>❌ PDB $pdb_name does not exist</p>" >> "$report_file"
    echo "<pre>Available PDBs:" >> "$report_file"
    sqlplus -s /nolog << EOF >> "$report_file"
connect $conn_str
SET PAGESIZE 1000
SET FEEDBACK OFF
SET LINESIZE 100
SET HEADING OFF
SELECT name || ' - ' || open_mode || ' - ' || restricted FROM v\$pdbs ORDER BY name;
EOF
    echo "</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi
}
#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!" >&2
  exit 1
fi

# Get default port
DEFAULT_PORT=$(grep '^PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
DEFAULT_PORT=${DEFAULT_PORT:-1521}

# Get email recipient
EMAIL_TO=$(sed -n '/^\[EMAIL\]/,/^$/p' "$CONFIG_FILE" | grep '^TO=' | cut -d'=' -f2)

# Initialize reports
REPORT_DIR="/tmp/pdb_reports_$(date +%Y%m%d%H%M%S)"
mkdir -p "$REPORT_DIR"
SUMMARY_FILE="$REPORT_DIR/pdb_migration_summary.html"
init_summary_report "$SUMMARY_FILE"

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Validate and parse the configuration line
  if ! validate_and_parse_line "$line"; then
    echo "Skipping invalid line: $line" >&2
    continue
  fi

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"
  
  # Verify connections
  if ! verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  # Get database properties
  src_properties=$(get_db_properties "$SRC_CONN")
  tgt_properties=$(get_db_properties "$TGT_CONN")
  
  # Run all compatibility checks
  check_version_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_compatibility_params "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_charset_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_platform_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_encryption_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_timezone_compatibility "$src_properties" "$tgt_properties" "$REPORT_FILE"
  check_max_string_size "$src_properties" "$tgt_properties" "$REPORT_FILE"
  
  # Finalize individual report
  finalize_html_report "$REPORT_FILE"
  
  # Add to summary report
  update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "COMPLETED"
done

# Finalize and send summary report
finalize_summary_report "$SUMMARY_FILE"

# Create zip archive of all reports
ZIP_FILE="/tmp/pdb_compatibility_reports_$(date +%Y%m%d%H%M%S).zip"
zip -q -j "$ZIP_FILE" "$REPORT_DIR"/*

# Send email with zip attachment
(
echo "To: $EMAIL_TO"
echo "Subject: PDB Migration Compatibility Reports"
echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: text/html"
echo
cat "$SUMMARY_FILE"
echo
echo "--MIXED_BOUNDARY"
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"$(basename "$ZIP_FILE")\""
echo "Content-Transfer-Encoding: base64"
echo
base64 "$ZIP_FILE"
echo
echo "--MIXED_BOUNDARY--"
) | sendmail -t

# Cleanup
rm -rf "$REPORT_DIR" "$ZIP_FILE"

exit 0

# Update verify_db_connection to include container check
verify_db_connection() {
  local conn_str=$1
  local type=$2
  local report_file=$3
  local pdb_name=$4

  echo "<div class='section'>" >> "$report_file"
  echo "<h2>Connection Verification: $type</h2>" >> "$report_file"

  # First verify we can connect to the CDB
  result=$(sqlplus -s /nolog << EOF
connect $conn_str
SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'SUCCESS' FROM dual;
EOF
  )

  if [[ "$result" != *"SUCCESS"* ]]; then
    echo "<p class='critical'>❌ Failed to connect to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
    echo "<pre>Error details: $result</pre>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi

  # Then verify we're connected to the correct PDB
  current_container=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SELECT sys_context('USERENV', 'CON_NAME') FROM dual;
EOF
  )

  if [[ "$current_container" != "$pdb_name" ]]; then
    echo "<p class='critical'>❌ Connected to wrong container: $current_container (expected: $pdb_name)</p>" >> "$report_file"
    echo "</div>" >> "$report_file"
    return 1
  fi

  conn_info=$(sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT 'Instance: ' || instance_name || 
       ' | Version: ' || version || 
       ' | Host: ' || host_name ||
       ' | CDB: ' || (SELECT cdb FROM v\$database) ||
       ' | Container: ' || sys_context('USERENV', 'CON_NAME')
FROM v\$instance;
EOF
  )
    
  echo "<p class='ok'>✅ Successfully connected to: $(echo "$conn_str" | sed 's/\"//g')</p>" >> "$report_file"
  echo "<p>Connection details: $conn_info</p>" >> "$report_file"
  echo "</div>" >> "$report_file"
  return 0
}

#!/bin/bash

# ... (previous configuration code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # Validate and parse the configuration line
  if ! validate_and_parse_line "$line"; then
    echo "Skipping invalid line: $line" >&2
    continue
  fi

  # Build Easy Connect strings
  SRC_CONN="sys@\"${SOURCE_SCAN}:${PORT}/${SOURCE_PDB}\" as sysdba"
  TGT_CONN="sys@\"${TARGET_SCAN}:${PORT}/${TARGET_PDB}\" as sysdba"

  # Initialize individual report
  REPORT_FILE="$REPORT_DIR/pdb_compatibility_${SOURCE_CDB}_${SOURCE_PDB}_to_${TARGET_CDB}_${TARGET_PDB}.html"
  init_html_report "$REPORT_FILE" "${SOURCE_CDB}/${SOURCE_PDB} to ${TARGET_CDB}/${TARGET_PDB}"

  # Verify connections and PDB existence
  if ! verify_db_connection "$SRC_CONN" "Source" "$REPORT_FILE" "$SOURCE_PDB"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! check_pdb_existence "$SRC_CONN" "$SOURCE_PDB" "Source" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "PDB_NOT_FOUND"
    continue
  fi

  if ! verify_db_connection "$TGT_CONN" "Target" "$REPORT_FILE" "$TARGET_PDB"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "CONNECTION_FAILED"
    continue
  fi

  if ! check_pdb_existence "$TGT_CONN" "$TARGET_PDB" "Target" "$REPORT_FILE"; then
    update_summary_report "$SUMMARY_FILE" "$SOURCE_CDB/$SOURCE_PDB" "$TARGET_CDB/$TARGET_PDB" "$REPORT_FILE" "PDB_NOT_FOUND"
    continue
  fi

  # ... (rest of the compatibility checks remain the same) ...
done

# ... (rest of the script remains the same) ...
update_summary_report() {
  local summary_file=$1
  local src_db="$2"
  local tgt_db="$3"
  local report_file="$4"
  local status="$5"
  
  report_filename=$(basename "$report_file")
  
  case "$status" in
    "CONNECTION_FAILED")
      echo "<tr class='critical'>
            <td>$src_db</td>
            <td>$tgt_db</td>
            <td>❌ Connection Failed</td>
            <td><a href='$report_filename'>View Details</a></td>
            <td>N/A</td>
          </tr>" >> "$summary_file"
      ;;
    "PDB_NOT_FOUND")
      echo "<tr class='critical'>
            <td>$src_db</td>
            <td>$tgt_db</td>
            <td>❌ PDB Not Found</td>
            <td><a href='$report_filename'>View Details</a></td>
            <td>N/A</td>
          </tr>" >> "$summary_file"
      ;;
    "COMPLETED")
      # Check for failures in the report
      if grep -q "class='critical'" "$report_file"; then
        critical_count=$(grep -c "class='critical'" "$report_file")
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='critical'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>❌ Failed ($critical_count issues)</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Critical: $critical_count<br>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      else
        warning_count=$(grep -c "class='warning'" "$report_file")
        
        echo "<tr class='ok'>
              <td>$src_db</td>
              <td>$tgt_db</td>
              <td>✅ Passed</td>
              <td><a href='$report_filename'>View Report</a></td>
              <td>Warnings: $warning_count</td>
            </tr>" >> "$summary_file"
      fi
      ;;
  esac
}
#!/bin/bash

# Function to get CDB-level parameters
get_cdb_parameters() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- CDB-specific parameters
prompt CDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE'
AND name NOT IN (
  'db_unique_name',
  'service_names',
  'local_listener',
  'remote_listener',
  'log_archive_dest_1',
  'log_archive_dest_2',
  'fal_server'
);
prompt CDB_PARAMETERS_END
EXIT;
EOF
}

# Function to get PDB-level parameters
get_pdb_parameters() {
  local conn_str=$1
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- PDB-specific parameters
prompt PDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN (
  'service_names',
  'local_listener',
  'db_file_name_convert',
  'log_file_name_convert'
);
prompt PDB_PARAMETERS_END
EXIT;
EOF
}

# Function to compare parameters and generate HTML
compare_parameters() {
  local src_params=$1
  local tgt_params=$2
  local title=$3
  local html_file=$4

  echo "<div class='section'>" >> "$html_file"
  echo "<h2>$title Parameter Comparison</h2>" >> "$html_file"
  echo "<table><tr><th>Parameter</th><th>Source Value</th><th>Target Value</th></tr>" >> "$html_file"

  awk -F= '
    BEGIN {count=0}
    NR==FNR {a[$1]=$2; next}
    {
      if ($1 in a) {
        if (a[$1] != $2) {
          printf "<tr><td>%s</td><td class=\"diff\">%s</td><td class=\"diff\">%s</td></tr>\n", $1,a[$1],$2
          count++
        }
        delete a[$1]
      } else {
        printf "<tr><td>%s</td><td>%s</td><td class=\"critical\">Missing</td></tr>\n", $1,$2
        count++
      }
    }
    END {
      for (i in a) {
        printf "<tr><td>%s</td><td class=\"critical\">Missing</td><td>%s</td></tr>\n", i,a[i]
        count++
      }
      exit (count > 0 ? 1 : 0)
    }
  ' <(echo "$src_params") <(echo "$tgt_params") >> "$html_file"

  if [ $? -eq 0 ]; then
    echo "<tr><td colspan='3' class='ok'>✅ All parameters match</td></tr>" >> "$html_file"
  fi

  echo "</table></div>" >> "$html_file"
}

# Function to extract parameters between markers
extract_parameters() {
  local full_output=$1
  local marker=$2
  awk -v marker="$marker" '
    $0 ~ marker "_START" {start=1; next}
    $0 ~ marker "_END" {exit}
    start {print}
  ' <<< "$full_output"
}

#!/bin/bash

# ... (previous configuration code remains the same) ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... (previous parsing and connection checks remain the same) ...

  # Get CDB and PDB parameters for both source and target
  src_full_output=$(get_db_properties "$SRC_CONN")
  tgt_full_output=$(get_db_properties "$TGT_CONN")

  # Extract and compare CDB parameters
  src_cdb_params=$(extract_parameters "$src_full_output" "CDB_PARAMETERS")
  tgt_cdb_params=$(extract_parameters "$tgt_full_output" "CDB_PARAMETERS")
  compare_parameters "$src_cdb_params" "$tgt_cdb_params" "CDB-Level" "$REPORT_FILE"

  # Extract and compare PDB parameters
  src_pdb_params=$(extract_parameters "$src_full_output" "PDB_PARAMETERS")
  tgt_pdb_params=$(extract_parameters "$tgt_full_output" "PDB_PARAMETERS")
  compare_parameters "$src_pdb_params" "$tgt_pdb_params" "PDB-Level" "$REPORT_FILE"

  # ... (rest of the compatibility checks remain the same) ...
done

# ... (rest of the script remains the same) ...
  
init_html_report() {
  local html_file="$1"
  local migration="$2"
  cat << EOF > "$html_file"
<html>
<head>
<title>PDB Compatibility Report: $migration</title>
<style>
  table {border-collapse: collapse; width: 100%; margin-bottom: 20px;}
  th, td {border: 1px solid #ddd; padding: 8px; text-align: left;}
  .critical {background-color: #f8d7da; color: #721c24;}
  .warning {background-color: #fff3cd; color: #856404;}
  .ok {background-color: #d4edda; color: #155724;}
  .diff {background-color: #ffe8e8;}
  .section {margin-bottom: 30px; border-top: 2px solid #444; padding-top: 15px;}
  h2 {color: #2c3e50;}
  h3 {color: #2c3e50; margin-top: 20px;}
</style>
</head>
<body>
<h1>PDB Compatibility Report: $migration</h1>
<p>Generated at: $(date)</p>
EOF
}
# Excluded parameters configuration
[EXCLUDED_PARAMS]
CDB_EXCLUDED=db_unique_name,service_names,local_listener,remote_listener,log_archive_dest_1,log_archive_dest_2,fal_server
PDB_EXCLUDED=service_names,local_listener,db_file_name_convert,log_file_name_convert

# ... rest of the configuration ...

#!/bin/bash

# Load excluded parameters from config
load_excluded_params() {
  local config_file=$1
  CDB_EXCLUDED=$(sed -n '/^\[EXCLUDED_PARAMS\]/,/^$/p' "$config_file" | grep '^CDB_EXCLUDED=' | cut -d'=' -f2)
  PDB_EXCLUDED=$(sed -n '/^\[EXCLUDED_PARAMS\]/,/^$/p' "$config_file" | grep '^PDB_EXCLUDED=' | cut -d'=' -f2)
}

# Function to get CDB-level parameters
get_cdb_parameters() {
  local conn_str=$1
  local excluded_params=$2
  
  # Convert comma-separated list to quoted SQL list
  sql_excluded=$(echo "$excluded_params" | sed "s/,/','/g")
  
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- CDB-specific parameters
prompt CDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'FALSE'
AND name NOT IN ('$sql_excluded');
prompt CDB_PARAMETERS_END
EXIT;
EOF
}

# Function to get PDB-level parameters
get_pdb_parameters() {
  local conn_str=$1
  local excluded_params=$2
  
  # Convert comma-separated list to quoted SQL list
  sql_excluded=$(echo "$excluded_params" | sed "s/,/','/g")
  
  sqlplus -s /nolog << EOF
connect $conn_str
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT OFF

-- PDB-specific parameters
prompt PDB_PARAMETERS_START
SELECT name || '=' || value 
FROM v\$parameter 
WHERE ispdb_modifiable = 'TRUE'
AND name NOT IN ('$sql_excluded');
prompt PDB_PARAMETERS_END
EXIT;
EOF
}

# ... rest of the functions remain the same ...
  
#!/bin/bash

# Source functions
source ./pdb_compatibility_functions.sh

# Load configuration
CONFIG_FILE=${1:-pdb_migrations.cfg}
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file $CONFIG_FILE not found!" >&2
  exit 1
fi

# Load excluded parameters
load_excluded_params "$CONFIG_FILE"

# ... rest of the configuration loading ...

# Process each migration line
grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep -v '^PORT=' | grep -v '^\[EMAIL\]' | while read -r line; do
  # ... previous parsing and connection checks ...

  # Get CDB and PDB parameters for both source and target
  src_full_output=$(get_db_properties "$SRC_CONN")
  tgt_full_output=$(get_db_properties "$TGT_CONN")

  # Extract and compare CDB parameters with excluded params
  src_cdb_params=$(extract_parameters "$(get_cdb_parameters "$SRC_CONN" "$CDB_EXCLUDED")" "CDB_PARAMETERS")
  tgt_cdb_params=$(extract_parameters "$(get_cdb_parameters "$TGT_CONN" "$CDB_EXCLUDED")" "CDB_PARAMETERS")
  compare_parameters "$src_cdb_params" "$tgt_cdb_params" "CDB-Level" "$REPORT_FILE"

  # Extract and compare PDB parameters with excluded params
  src_pdb_params=$(extract_parameters "$(get_pdb_parameters "$SRC_CONN" "$PDB_EXCLUDED")" "PDB_PARAMETERS")
  tgt_pdb_params=$(extract_parameters "$(get_pdb_parameters "$TGT_CONN" "$PDB_EXCLUDED")" "PDB_PARAMETERS")
  compare_parameters "$src_pdb_params" "$tgt_pdb_params" "PDB-Level" "$REPORT_FILE"

  # ... rest of the compatibility checks ...
done

# ... rest of the script ...
