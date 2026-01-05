#!/system/bin/sh

MODDIR=${0%/*}

core="$MODDIR/weix"
script="$MODDIR/boot-completed.sh"

user_dir='/data/user'
ap_config='/data/adb/ap/package_config'
ts_config='/data/adb/tricky_store/target.txt'

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
  [ -n "$1" ] && echo "$1" >>"$ap_config"
}

filter_config() {
  get_manager
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
  {
    sed 's/[!?]$//' "$ts_config"
    echo "${1:-$(
      pm list packages -3 2>/dev/null |
      awk -F ':' '{print $2}'
    )}"
  } | sort -u >"$tmp" && mv "$tmp" "$ts_config"
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
  case "$1" in
  *n*)
    sleep 1
    add_new_app $2 $3
    [ "${2##*/}" -eq 0 ] && [ -f "$ts_config" ] && add_ts_config "$3"
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
