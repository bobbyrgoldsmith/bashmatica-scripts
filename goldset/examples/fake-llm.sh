#!/usr/bin/env bash
# Stand-in model: canned answers keyed on the prompt, so the demo runs offline.
p="$(cat)"
case "$p" in
  *"grand total"*) echo "90.00" ;;
  *"refund window"*) echo "Our stated refund window is 30 days from delivery." ;;
  *"SAVE10"*) echo "The final total after the 10% discount is 72.0" ;;
  *) echo "I don't know." ;;
esac
