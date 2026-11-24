#!/usr/bin/env bash
# Create a project or a unit under the threads folder.
# Usage:
#   new.sh project <name> <summary> [path...]
#   new.sh unit <project> <name> <summary>
# Prints the path of the new state.md.
# Exit codes: 0 created, 2 bad usage or invalid name, 3 project missing, 4 already exists.
# Everything is validated before the first folder is made, so a non-zero exit writes nothing.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
  {
    echo "usage: new.sh project <name> <summary> [path...]"
    echo "       new.sh unit <project> <name> <summary>"
  } >&2
  exit 2
}

# Make a folder that must not exist yet; exit 4 if it does, including when another session wins the race.
make_new_dir() {
  if [ -e "$1" ] || ! mkdir "$1" 2>/dev/null; then
    echo "already exists: $1" >&2
    exit 4
  fi
}

create_project() {
  [ "$#" -ge 2 ] || usage
  local name="$1" summary path dir
  valid_name "$name" || { echo "invalid name: $name" >&2; exit 2; }
  summary="$(one_line "$2")"
  shift 2
  [ -n "$summary" ] || usage
  for path in "$@"; do
    [ -n "$path" ] || usage
  done
  dir="$(threads_dir)/projects/$name"
  [ ! -e "$dir" ] || { echo "already exists: $dir" >&2; exit 4; }

  mkdir -p "$(threads_dir)/projects" || exit 1
  make_new_dir "$dir"
  mkdir "$dir/units" || exit 1
  {
    printf -- '---\nname: %s\nsummary: %s\n' "$name" "$summary"
    if [ "$#" -gt 0 ]; then
      printf 'paths:\n'
      for path in "$@"; do printf '  - %s\n' "$path"; done
    fi
    printf 'status: active\n---\n'
  } > "$dir/state.md" || exit 1
  printf '%s\n' "$dir/state.md"
}

create_unit() {
  [ "$#" -eq 3 ] || usage
  local project="$1" name="$2" summary pdir dir
  valid_name "$project" || { echo "invalid project name: $project" >&2; exit 2; }
  valid_name "$name" || { echo "invalid name: $name" >&2; exit 2; }
  summary="$(one_line "$3")"
  [ -n "$summary" ] || usage
  pdir="$(threads_dir)/projects/$project"
  [ -d "$pdir" ] || { echo "no such project: $project" >&2; exit 3; }
  dir="$pdir/units/$name"
  [ ! -e "$dir" ] || { echo "already exists: $dir" >&2; exit 4; }

  mkdir -p "$pdir/units" || exit 1
  make_new_dir "$dir"
  {
    printf -- '---\nname: %s\nsummary: %s\nstatus: active\n---\n\n## Where to continue\n\n' "$name" "$summary"
  } > "$dir/state.md" || exit 1
  printf '%s\n' "$dir/state.md"
}

[ "$#" -ge 1 ] || usage
cmd="$1"
shift
case "$cmd" in
  project) create_project "$@" ;;
  unit) create_unit "$@" ;;
  *) usage ;;
esac
