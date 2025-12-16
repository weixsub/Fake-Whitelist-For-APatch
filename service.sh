#!/system/bin/sh

MODDIR="${0%/*}"

file="$MODDIR/WeiX"
script="$MODDIR/service.sh"

user_path="/data/user"
pkgs_path="/data/system/packages.list"
config_path="/data/adb/ap/package_config"

update_config() {
  [ -n "$1" ] && printf "%s\n" "$1" >>"$config_path"
}

filter_config() {
  awk -F ',' '
    FNR==NR {
      if (FNR==1) next
      list[$1":"$4]
      next
    }
    {
      if (!($0 in list)) {
        split($0, i, ":")
        printf "%s,1,0,%s,0,u:r:untrusted_app:s0\n", i[1], i[2]
      }
    }
  ' "$config_path" -
}

exclude_user_app() {
  update_config "$(
    find "$user_path" -mindepth 2 -maxdepth 2 -type d 2>/dev/null |
      awk '
      FNR == NR {
        pkg = $1
        uid[pkg] = $2

        if ($NF == "@system")
          type[pkg] = "sys"
        else
          type[pkg] = "user"

        next
      }
      {
        n = split($0, p, "/")
        pkg  = p[n]
        sid = (p[n-1] == 0 ? "" : p[n-1])
        if (type[pkg] == "user") print pkg ":" sid uid[pkg]
      }
    ' "$pkgs_path" - | filter_config
  )"
}

monitor() {
  ps -eo cmd | grep -qx "WeiX_${1##*/}" && exit 0
  link="$file"_"${1##*/}"
  ln -s "$file" "$link"
  "$link" "$1" "$script" "${2:-0}" &
}

monitor_new_app() {
  for path in "$user_path"/*; do
    [ -d "$path" ] || continue
    monitor "$path"
  done
}

monitor_new_user() {
  monitor "$user_path" 1
}

if [ "$1" = "install" ]; then
  exclude_user_app
  exit 0
fi

if [ "$#" -eq 2 ]; then
  case "$2" in
  '' | *[!0-9]*)
    update_config "$(
      awk -v sid="${1##*/}" -v pkg="$2" '
        $1 == pkg && $NF != "@system" {
          print $1 ":" (sid == 0 ? "" : sid) $2
        }
      ' "$pkgs_path" | filter_config
    )"
    ;;
  *)
    monitor "$1/$2"
    ;;
  esac
  exit 0
fi

exclude_user_app
monitor_new_app
monitor_new_user
