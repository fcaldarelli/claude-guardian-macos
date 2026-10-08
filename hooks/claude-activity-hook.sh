#!/bin/bash
# claude-activity-hook.sh
#
# Hook per Claude Code: registra lo stato di ogni sessione in
# ~/.claude/activity/<session_id>.json, così un'app nella barra dei menu
# può contare quante sessioni stanno lavorando.
#
# Va registrato (senza argomenti) sugli eventi:
#   SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
#   Notification, Stop, SessionEnd
#
# IMPORTANTE: per UserPromptSubmit e SessionStart Claude Code aggiunge
# l'output del comando al contesto, quindi questo script non deve
# stampare nulla su stdout.

set -u

DIR="${CLAUDE_ACTIVITY_DIR:-$HOME/.claude/activity}"
INPUT="$(cat)"

# Da qui in poi nessun output verso Claude Code.
exec 1>/dev/null 2>/dev/null

mkdir -p "$DIR" || exit 0

# Legge un campo di primo livello dal JSON ricevuto su stdin.
# Usa jq se c'è (incluso in macOS 15+), altrimenti plutil (sempre presente su macOS).
get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty | tostring'
  else
    printf '%s' "$INPUT" | plutil -extract "$1" raw -o - - 2>/dev/null
  fi
}

# Escape minimo per inserire una stringa in JSON.
json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Risale l'albero dei processi e ricava:
#  CLAUDE_PID  il processo di Claude Code (per scartare sessioni morte: crash, terminale chiuso)
#  APP_PATH    il bundle .app che l'ha lanciata (Terminal, iTerm, VS Code, IntelliJ, ...)
#  TTY         il terminale della sessione, per riportare in primo piano proprio quella scheda
# Su macOS "ps -o comm=" restituisce il percorso completo dell'eseguibile.
inspect_process_tree() {
  local pid=$PPID comm i
  CLAUDE_PID=""; APP_PATH=""; APP_PID=0; TTY=""
  for i in $(seq 1 25); do
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)" || break
    [ -n "$comm" ] || break
    if [ -z "$CLAUDE_PID" ]; then
      case "$(basename "$comm")" in
        *claude*|*node*) CLAUDE_PID="$pid" ;;
      esac
    fi
    if [ -z "$APP_PATH" ] && [[ "$comm" == *".app/"* ]]; then
      # Prende il bundle più esterno: ".../Visual Studio Code.app/Contents/Frameworks/Code Helper.app/..."
      APP_PATH="${comm%%.app/*}.app"
      APP_PID="$pid"
      break
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [ -z "$pid" ] || [ "$pid" -le 1 ]; then break; fi
  done
  [ -n "$CLAUDE_PID" ] || CLAUDE_PID="$PPID"
  TTY="$(ps -o tty= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')"
  case "$TTY" in ""|"?"|"??") TTY="" ;; *) TTY="/dev/${TTY#/dev/}" ;; esac
}

# Risale da una cartella fino alla radice del progetto (.idea, .vscode o .git).
# Serve quando Claude è stato lanciato in una sottocartella: l'editor riconosce
# come "già aperto" il progetto, non la sottocartella.
find_project_root() {
  local d="$1" m
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
    for m in .idea .vscode .git; do
      if [ -e "$d/$m" ]; then printf '%s' "$d"; return; fi
    done
    d="$(dirname "$d")"
  done
  printf '%s' "$1"
}

SID="$(get session_id | tr -cd 'A-Za-z0-9_-')"
[ -n "$SID" ] || exit 0

EVENT="$(get hook_event_name)"
FILE="$DIR/$SID.json"

case "$EVENT" in
  SessionStart)
    STATE="idle" ;;
  UserPromptSubmit|PreToolUse|PostToolUse)
    STATE="working" ;;
  Notification)
    NTYPE="$(get notification_type)"
    MSG="$(get message)"
    if [ "$NTYPE" = "idle_prompt" ] || [[ "$MSG" == *"waiting for your input"* ]]; then
      STATE="idle"      # Claude ha finito e aspetta un nuovo prompt
    else
      STATE="waiting"   # Claude aspetta un permesso o una risposta
    fi ;;
  Stop)
    STATE="idle" ;;
  SessionEnd)
    rm -f "$FILE"
    exit 0 ;;
  *)
    exit 0 ;;
esac

RAW_CWD="$(get cwd)"
CWD="$(json_escape "$RAW_CWD")"
ROOT="$(json_escape "$(find_project_root "$RAW_CWD")")"
TRANSCRIPT="$(json_escape "$(get transcript_path)")"
inspect_process_tree
APP="$(json_escape "$APP_PATH")"
NOW="$(date +%s)"

TMP="$DIR/.$SID.$$.tmp"
printf '{"session_id":"%s","state":"%s","event":"%s","cwd":"%s","project_root":"%s","transcript_path":"%s","pid":%s,"app_path":"%s","app_pid":%s,"tty":"%s","updated_at":%s}\n' \
  "$SID" "$STATE" "$EVENT" "$CWD" "$ROOT" "$TRANSCRIPT" "${CLAUDE_PID:-0}" "$APP" "${APP_PID:-0}" "$TTY" "$NOW" > "$TMP" && mv -f "$TMP" "$FILE"

exit 0
