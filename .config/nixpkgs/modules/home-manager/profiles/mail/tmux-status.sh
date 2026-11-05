if ! accounts=$(@updateMail@ --status); then
    printf '?'
    exit 1
fi

labels=
while IFS= read -r account; do
    case "$account" in
        '') continue ;;
        personal) label=p ;;
        shared) label=s ;;
        tommoa) label=t ;;
        work) label=w ;;
        *) label='?' ;;
    esac
    labels="${labels}${labels:+,}${label}"
done <<EOF
$accounts
EOF

printf '%s' "$labels"
