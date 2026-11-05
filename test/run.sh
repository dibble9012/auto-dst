#!/bin/bash
# Off-car test of mod/dst.sh with a fake service and getprop. No mksh on the Mac, so
# it runs under bash; `dst.sh check <epoch>` only reports, so nothing else is faked.
#   test/run.sh
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export T PATH="$T/bin:$PATH"
mkdir "$T/bin"

cat > "$T/bin/service" <<'EOF'
#!/bin/bash
echo "Result: Parcel(00000000 00000001   '........')"
EOF
cat > "$T/bin/getprop" <<'EOF'
#!/bin/bash
cat "$T/zone"
EOF
chmod +x "$T/bin/"*

# the script reads /data/hmgapi/settings/<mod>.json; point it at a file here
sed "s|^SETTINGS=.*|SETTINGS=$T/settings.json|" "$HERE/mod/dst.sh" > "$T/dst.sh"

fails=0
t() {  # t <rule> <zone> <UTC date> <wanted>
    local e got
    e=$(date -u -j -f '%Y-%m-%d %H:%M:%S' "$3" +%s)
    echo "{\"rule\":\"$1\",\"notify\":false}" > "$T/settings.json"
    echo "$2" > "$T/zone"
    got=$(bash "$T/dst.sh" check "$e" 2>&1)
    case "$got" in
    *"wanted $4"*) ;;
    *) echo "FAIL $1 $2 $3 want $4: $got"; fails=$((fails + 1)) ;;
    esac
}

E=Mobis/UTC-05:00
t us $E '2026-11-01 05:59:59' 1      # 1:59:59 daylight, the last second
t us $E '2026-11-01 06:00:00' 0
t us $E '2027-03-14 06:59:59' 0
t us $E '2027-03-14 07:00:00' 1
t us $E '2026-03-08 07:00:00' 1
t us $E '2026-07-04 12:00:00' 1
t us $E '2026-12-25 12:00:00' 0
t us $E '2028-11-05 05:59:59' 1
t us $E '2028-11-05 06:00:00' 0
t us Mobis/UTC-08:00 '2026-11-01 08:59:59' 1
t us Mobis/UTC-08:00 '2026-11-01 09:00:00' 0
t eu Mobis/UTC+01:00 '2026-03-29 00:59:59' 0
t eu Mobis/UTC+01:00 '2026-03-29 01:00:00' 1
t eu Mobis/UTC+01:00 '2026-10-25 00:59:59' 1
t eu Mobis/UTC+01:00 '2026-10-25 01:00:00' 0
t never $E '2026-07-04 12:00:00' 0

# a zone it can't read is left alone
echo '{"rule":"us"}' > "$T/settings.json"; echo Asia/Seoul > "$T/zone"
case "$(bash "$T/dst.sh" check 1783166400 2>&1)" in
*"leaving DST alone"*) ;;
*) echo "FAIL other zone not left alone"; fails=$((fails + 1)) ;;
esac

[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
