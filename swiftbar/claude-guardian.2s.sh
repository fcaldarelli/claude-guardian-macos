#!/bin/bash
# Plugin SwiftBar/xbar: prova rapida senza compilare l'app.
# Copialo nella cartella plugin di SwiftBar; il "2s" nel nome = aggiorna ogni 2 secondi.
# Clic su una sessione: porta in primo piano l'app da cui è stata lanciata.

DIR="$HOME/.claude/activity"
working=0; waiting=0; total=0; lines=""

field() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p"; }

for f in "$DIR"/*.json; do
  [ -e "$f" ] || continue
  json="$(cat "$f")"
  state="$(field "$json" state)"
  pid="$(field "$json" pid)"
  cwd="$(field "$json" cwd)"
  app="$(field "$json" app_path)"
  root="$(field "$json" project_root)"; [ -n "$root" ] || root="$cwd"
  if [ -n "$pid" ] && [ "$pid" != "0" ] && ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"; continue   # processo non più vivo
  fi
  total=$((total+1))
  case "$state" in
    working) working=$((working+1)); icon="⚙️"; label="working" ;;
    waiting) waiting=$((waiting+1)); icon="✋"; label="waiting for you" ;;
    *) icon="💤"; label="idle" ;;
  esac
  if [ -n "$app" ]; then
    action="bash=/usr/bin/open param1=-a param2=\"$app\" terminal=false"
    appname=" · $(basename "$app" .app)"
  else
    action="bash=/usr/bin/open param1=\"$cwd\" terminal=false"
    appname=""
  fi
  lines+="$icon $(basename "$root") — $label$appname | $action"$'\n'
done

if [ "$total" -eq 0 ]; then echo "✳︎"; else echo "⚙️ $working ✋ $waiting"; fi
echo "---"
echo "Working: $working · Waiting for you: $waiting"
echo "---"
if [ -n "$lines" ]; then printf '%s' "$lines"; else echo "No active Claude Code sessions"; fi
