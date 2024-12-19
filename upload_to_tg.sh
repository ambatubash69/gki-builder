
[ -z "$TOKEN" ] && echo "[ERROR] Bot token is not defined!" && ret=1
[ -z "$CHAT_ID" ] && echo "[ERROR] Chat ID is not defined!" && ret=$((ret + 1))
[ -n "$ret" ] && exit $ret

file="$1"

if [[ -f "$file" ]]; then
    chmod 777 "$file"
else
    echo "[ERROR] file $file doesn't exist"
    exit 1
fi

curl -s -F document=@"$file" "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=markdown"