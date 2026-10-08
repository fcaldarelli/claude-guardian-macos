#!/bin/bash
# Installa l'hook in ~/.claude/hooks e lo registra in ~/.claude/settings.json.
# Rieseguibile senza duplicare le voci. Fa un backup di settings.json.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/activity"
cp "$HERE/hooks/claude-activity-hook.sh" "$CLAUDE_DIR/hooks/claude-activity-hook.sh"
chmod +x "$CLAUDE_DIR/hooks/claude-activity-hook.sh"
echo "✓ Hook copiato in $CLAUDE_DIR/hooks/"

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠ jq non trovato (è incluso da macOS 15, oppure: brew install jq)."
  echo "  Aggiungi a mano il contenuto di hooks/hooks-settings.json in $SETTINGS"
  exit 0
fi

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

# Per ogni evento: toglie eventuali voci precedenti di questo hook e aggiunge quelle nuove.
jq --slurpfile add "$HERE/hooks/hooks-settings.json" '
  reduce ($add[0].hooks | to_entries[]) as $e (.;
    .hooks[$e.key] = (
      ((.hooks[$e.key] // [])
        | map(select((.hooks // []) | all((.command // "") | contains("claude-activity-hook") | not))))
      + $e.value
    )
  )' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "✓ Hook registrati in $SETTINGS (backup accanto al file)"
echo "  Le sessioni Claude Code già aperte li useranno dopo il riavvio."
