#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF before deployment}"

# Requires Supabase CLI login/link. Configure provider secrets separately in Supabase.
# User functions keep JWT verification; service/webhook functions authenticate themselves.
for fn in quiz-validate award-xp vote-next-book ai-recommendations ai-user-embeddings match-readers social-render-card newsletter-dispatch; do
  supabase functions deploy "$fn" --project-ref "$SUPABASE_PROJECT_REF"
done
supabase functions deploy scheduled-reminders --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"
supabase functions deploy stripe-webhook --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"
