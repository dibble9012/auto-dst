#!/system/bin/sh
# Auto DST: flips the clock's Daylight Saving Time switch on the right dates.
#
# The switch belongs to the MICOM time service (com.hkmc.micom.time, the
# TimePolicyManager.setDst() that Settings, Clock calls). The zone itself stays a
# fixed standard offset (persist.sys.timezone = Mobis/UTC-05:00); with DST on, the
# service runs the system clock one hour ahead instead. So while DST is on, real
# UTC is the clock minus an hour.
#
# Usage: dst.sh            run as the mod's service (checks once a minute)
#        dst.sh check [s]  print what it would do now, or at real UTC epoch s
#
# mksh only: the head unit has no sed, cut or expr. Its arithmetic is 32-bit,
# which holds until 2038.

SVC=com.hkmc.micom.time
SETTINGS=/data/hmgapi/settings/${HMGAPI_MOD:-auto-dst}.json
GS=com.android.generalsettings
PREFS=/data/data/$GS/shared_prefs

log() { echo "$(date '+%m-%d %H:%M:%S') $*"; }

setting() {   # setting <key> <default>, from settings JSON like {"rule":"eu","notify":false}
    local j v
    j=$(cat "$SETTINGS" 2>/dev/null); v=${j#*\"$1\":}
    [ "$v" = "$j" ] && { echo "$2"; return; }
    v=${v# }; v=${v#\"}; v=${v%%[\",\}]*}
    echo "${v:-$2}"
}

svc_bool() {  # a boolean binder reply, "Result: Parcel(00000000 00000001 ..." -> 1
    case "$(service call $SVC $1 2>/dev/null)" in
    *"(00000000 00000001"*) echo 1 ;;
    *"(00000000 00000000"*) echo 0 ;;
    esac
}

std_offset() {  # the zone's standard offset in seconds, from Mobis/UTC-05:00
    local tz o h m
    tz=$(getprop persist.sys.timezone)
    case "$tz" in Mobis/UTC[+-][0-9][0-9]:[0-9][0-9]) ;; *) return 1 ;; esac
    o=${tz#Mobis/UTC}; h=${o#?}; h=${h%:*}; m=${o#*:}
    h=$(( (10#$h * 3600) + (10#$m * 60) ))
    case "$o" in -*) echo $(( -h )) ;; *) echo $h ;; esac
}

days() {      # days <y> <m> <d>: days since 1970-01-01 (Howard Hinnant's days_from_civil)
    local y=$1 m=$2 era yoe doy
    [ $m -le 2 ] && y=$(( y - 1 ))
    era=$(( y / 400 )); yoe=$(( y - era * 400 ))
    doy=$(( (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + $3 - 1 ))
    echo $(( era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468 ))
}

year_of() {   # year_of <days since 1970-01-01>
    local z=$(( $1 + 719468 )) era doe yoe doy
    era=$(( z / 146097 )); doe=$(( z - era * 146097 ))
    yoe=$(( doe - doe / 1460 + doe / 36524 - doe / 146096 )); yoe=$(( yoe / 365 ))
    doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
    echo $(( yoe + era * 400 + ((5 * doy + 2) / 153 >= 10) ))
}

# day numbers of Sundays; 1970-01-01 was a Thursday, so (d + 4) % 7 is 0 on Sunday
nth_sunday()  { local f=$(days $1 $2 1); echo $(( f + (7 - (f + 4) % 7) % 7 + 7 * ($3 - 1) )); }
last_sunday() { local l=$(( $(days $1 $(( $2 + 1 )) 1) - 1 )); echo $(( l - (l + 4) % 7 )); }

wanted() {    # wanted <rule> <real UTC epoch> <standard offset>: 1 if DST is in effect
    local y s e
    y=$(year_of $(( ($2 + $3) / 86400 )))
    case $1 in
    us) # 2 AM standard time to 2 AM daylight time (= 1 AM standard)
        s=$(( $(nth_sunday $y 3 2) * 86400 + 7200 - $3 ))
        e=$(( $(nth_sunday $y 11 1) * 86400 + 3600 - $3 )) ;;
    eu) # 01:00 UTC both ways
        s=$(( $(last_sunday $y 3) * 86400 + 3600 ))
        e=$(( $(last_sunday $y 10) * 86400 + 3600 )) ;;
    *)  echo 0; return ;;
    esac
    [ $2 -ge $s ] && [ $2 -lt $e ] && echo 1 || echo 0
}

pref_set() {  # pref_set <prefs xml> <boolean name> <true|false>; rewrites in place so owner and mode stay
    local out="" line
    [ -f "$1" ] || return
    while IFS= read -r line; do
        case "$line" in *"name=\"$2\""*) line="    <boolean name=\"$2\" value=\"$3\" />" ;; esac
        out="$out$line
"
    done < "$1"
    print -nr -- "$out" > "$1"
}

sync_screen() {  # make Settings, Clock show the switch as it is
    local v=false u pid rest
    [ $1 = 1 ] && v=true
    case "$(cat $PREFS/RegPrefDST.xml 2>/dev/null)" in
    "") return ;;
    *"name=\"RegKeyDST\" value=\"$v\""*) return ;;
    esac
    # Settings keeps its prefs in memory, so it has to restart to see the change;
    # not while it's on screen (it comes back by itself: its service is sticky)
    case "$(dumpsys window windows | grep mCurrentFocus)" in *$GS*) return ;; esac
    pref_set $PREFS/RegPrefDST.xml RegKeyDST $v
    pref_set $PREFS/RegInitValue.xml savevalue_dst $v
    ps | while read u pid rest; do
        case "$rest" in *" $GS") kill $pid ;; esac
    done
    log "Settings, Clock now shows DST $v"
}

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1
}

step() {      # step [real UTC epoch]: one check; prints what it found
    local rule have now real off want
    rule=$(setting rule us)
    have=$(svc_bool 3)
    [ -n "$have" ] || { echo "time service not answering"; return 1; }
    [ "$(svc_bool 5)" = 1 ] || { echo "no real time yet (GPS/network)"; return 1; }
    off=$(std_offset) || { echo "zone $(getprop persist.sys.timezone) isn't Mobis/UTC+-hh:mm; leaving DST alone"; return 1; }
    now=$(date +%s)
    real=${1:-$(( now - 3600 * have ))}
    want=$(wanted $rule $real $off)
    [ -n "$1" ] && echo "at real UTC $real:"
    echo "rule $rule, standard offset $off s, DST $have, wanted $want"
    [ "$want" = "$have" ] && return 0
    [ -n "$1" ] && return 0          # check at a given time: report only
    service call $SVC 4 i32 $want >/dev/null
    log "DST $have -> $want"
    if [ "$(setting notify true)" = true ]; then
        [ $want = 1 ] && toast "Clock changed to daylight saving time" || toast "Clock changed to standard time"
    fi
}

if [ "$1" = check ]; then
    step "$2"
    exit 0
fi

log "started"
while :; do
    msg=$(step)
    [ "$msg" != "$last" ] && log "$msg"   # log only changes, not every minute
    last=$msg
    have=$(svc_bool 3)
    [ -n "$have" ] && sync_screen $have
    sleep 60
done
