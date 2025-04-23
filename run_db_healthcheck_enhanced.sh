
send_email() {
  local host_entry="$1"
  local report_file="$2"

  local max_inline_size=2097152  # 2MB in bytes
  local file_size
  file_size=$(stat -c%s "$report_file")

  if [[ "$file_size" -le "$max_inline_size" ]]; then
    # Send as HTML body
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $EMAIL_SUBJECT - $host_entry"
      echo "Content-Type: text/html"
      echo
      cat "$report_file"
    } | sendmail -t
    log_msg "Email sent as inline HTML for $host_entry"
  else
    # Send as attachment
    {
      echo "To: $EMAIL_RECIPIENT"
      echo "Subject: $EMAIL_SUBJECT - $host_entry (Attached)"
      echo "MIME-Version: 1.0"
      echo "Content-Type: multipart/mixed; boundary="MIXED-BOUNDARY""
      echo
      echo "--MIXED-BOUNDARY"
      echo "Content-Type: text/plain"
      echo
      echo "Health check report is attached for $host_entry (size exceeds 2MB)."
      echo
      echo "--MIXED-BOUNDARY"
      echo "Content-Type: text/html; name="$(basename "$report_file")""
      echo "Content-Disposition: attachment; filename="$(basename "$report_file")""
      echo "Content-Transfer-Encoding: base64"
      echo
      base64 "$report_file"
      echo "--MIXED-BOUNDARY--"
    } | sendmail -t
    log_msg "Email sent with attachment for $host_entry (file too large)"
  fi
}
