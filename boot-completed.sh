#!/system/bin/sh

MODDIR=${0%/*}

core="$MODDIR/weix"
script="$MODDIR/boot-completed.sh"

user_dir='/data/user'
ap_config='/data/adb/ap/package_config'
ts_config='/data/adb/tricky_store/target.txt'

get_ap_config() {
  ap_config="$(
    find '/data/adb' -mindepth 2 -maxdepth 2 -type f -name 'package_config'
  )"
  [ "$(echo "$ap_config" | wc -l)" -eq 1 ] && return 0

  ap_config="$(
    echo "$ap_config" |
      while read -r path; do
        [ -f "${path%/*}/bin/busybox" ] && echo "$path"
      done
  )"
  [ "$(echo "$ap_config" | wc -l)" -eq 1 ] && return 0

  ap_config="$(
    echo "$(
      echo "$ap_config" |
        while read -r v; do
          stat -c '%Y %n' "$v"
        done
    )" |
      awk '
      $1 > max {
        max = $1
        file = $2
      }
      END {
        print file
      }
    '
  )"

  [ -z "$ap_config" ] && exit
}

get_manager() {
  manager="$(
    find '/data/app' -mindepth 4 -maxdepth 5 -type f -name 'libapd.so' |
      awk -F '/' '{
      sub(/-.*/, "", $(NF-3))
      print $(NF-3)
    }'
  )"
  [ -n "$manager" ] && return 0

  manager="$(
    dumpsys package |
      awk -F '[][]' -v ver="$APATCH_VER_CODE" '
      /Package \[/ {pkg = $2}
      /codePath/ {path = $0; gsub(/ |codePath=/, "", path)}
      $0 ~ "versionCode=" ver {print pkg, path}
    '
  )"
  if [ "$(echo "$manager" | wc -l)" -eq 1 ]; then
    manager="${manager%% *}"
  else
    manager="$(
      echo "$manager" |
        while read -r pkg path; do
          so="$path/lib/arm64/libapd.so"
          [ -f "$so" ] && echo "$pkg"
        done
    )"
  fi
}

update_config() {
  [ -f "$ap_config" ] || get_ap_config
  [ -n "$1" ] && echo "$1" >>"$ap_config"
}

filter_config() {
  [ -f "$ap_config" ] || get_ap_config
  [ -n "$manager" ] || get_manager
  awk -F '[, ]' -v m="$manager" '
    BEGIN {
      split(m, pkg, "\n")
      for (i in pkg) apm[pkg[i]]
    }
    FNR == NR {
      if (FNR==1) next
      map[$1, $4]
      next
    }
    ! (($1, $2) in map) && ! ($1 in apm) {
      printf "%s,1,0,%s,0,u:r:untrusted_app:s0\n", $1, $2
    }
  ' "$ap_config" -
}

add_ap_config() {
  update_config "$(
    pm list packages --user all -3 -U 2>/dev/null |
      awk -F '[: ]' '{
      split($4, uid, ",")
      for (i in uid) print $2, uid[i]
    }' | filter_config
  )"
  [ -f "$ts_config" ] && add_ts_config
}

add_ts_config() {
  tmp="$(mktemp)"
  tsc_status="$([ -s "$ts_config" ] && echo 1 || echo 0)"
  {
    echo "${1:-$(
      base_pkg="
        com.android.vending
        com.google.android.gms
        com.google.android.gsf
        com.heytap.speechassist
        com.coloros.sceneservice
        com.oplus.deepthinker
      "
      echo "$(
        pm list packages -s 2>/dev/null |
          awk -F ':' -v base="$(echo "$base_pkg" | tr '\n' '|')" '
          BEGIN {
            split(base, pkg, "|")
            for (i in pkg) {
              sub(/ +/, "", pkg[i])
              if (pkg[i] != "") map[pkg[i]]
            }
          }
          $2 in map {
            print ":"$2
          }
        '
      )"
      pm list packages -3 2>/dev/null
    )}"
  } |
    awk -F ':' -v tsc_stat="$tsc_status" '
    FNR == NR && tsc_stat == 1 {
      line = pkg = $0
      sub(/[\r!?]+$/, "", pkg)
      if (pkg != "") map[pkg] = line
      next
    }
    !($2 in map) {
      map[$2] = $2
    }
    END {
      for (pkg in map) print map[pkg]
    }
  ' "$ts_config" - | sort >"$tmp" && mv "$tmp" "$ts_config"
}

add_new_app() {
  update_config "$(
    pm list packages --user "${1##*/}" -3 -U "$2" 2>/dev/null |
      awk -F '[: ]' '{print $2, $4}' | filter_config
  )"
}

monitor() {
  for pid in $(ps -eo comm,pid | awk '$1=="weix" {print $2}'); do
    dir="$(tr '\0' ' ' <"/proc/$pid/cmdline" | awk '{print $3}')"
    [ "$dir" = "$1" ] && return 0
  done
  "$core" "$script" "$1" "$2" &
}

start_monitor() {
  monitor "$user_dir" m
  for path in "$user_dir"/*; do
    [ -d "$path" ] || continue
    monitor "$path" n
  done
}

if [ "$#" -eq 3 ]; then
  sleep 1
  case "$1" in
  *n*)
    add_new_app $2 $3
    [ "${2##*/}" -eq 0 ] && [ -f "$ts_config" ] && add_ts_config ":$3"
    ;;
  *m*)
    add_new_app $3
    monitor "$2/$3" n
    ;;
  esac
  exit
fi

if [ "$1" = "i" ]; then
  add_ap_config
  exit
fi

add_ap_config
start_monitor
exit
