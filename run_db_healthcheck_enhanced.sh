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
