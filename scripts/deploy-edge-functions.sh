#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF before deployment}"

# Requires Supabase CLI login/link. Configure provider secrets separately in Supabase.
# JWT verification stays enabled by default; Stripe verifies its own webhook signature.
for fn in quiz-validate award-xp vote-next-book scheduled-reminders ai-recommendations match-readers social-render-card newsletter-dispatch; do
  supabase functions deploy "$fn" --project-ref "$SUPABASE_PROJECT_REF"
done
supabase functions deploy stripe-webhook --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"

# ai-user-embeddings is omitted: the RPC now exists, but deployment still requires
# authentication/ownership validation for user_id, privacy review of the snapshot,
# configured secrets, and tests. Do not add it to the loop until those gates pass.
