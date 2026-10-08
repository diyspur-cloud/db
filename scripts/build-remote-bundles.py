#!/usr/bin/env python3
"""Concatenate ordered, individually reviewable SQL migrations into apply_migration bundles."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=root/'supabase/migrations'
out=root/'supabase/deploy-bundles'; out.mkdir(parents=True,exist_ok=True)
groups={
 '001_foundation':['20260101000000_extensions_and_enums.sql',*[f'20260101{i:04d}00_{suffix}.sql' for i,suffix in [(1,'profiles'),(2,'books_and_authors'),(3,'seasons_and_chapters'),(4,'meetings'),(5,'progress'),(6,'comments_and_reactions'),(7,'quiz'),(8,'gamification'),(9,'polls_and_votes'),(10,'achievements'),(11,'notifications'),(12,'p2_tables')]],],
 '002_base_security_and_functions':['20260101001300_rls_policies.sql','20260101001400_functions_and_triggers.sql'],
 '003_realtime_and_storage':['20260101001500_realtime.sql','20260101001600_storage.sql'],
 '004_complement_schema':['20260101001650_extensions_and_enums_complement.sql','20260101001651_storage_complement.sql',*[f'20260101{i:04d}00_{suffix}.sql' for i,suffix in [(17,'book_metadata_and_reading'),(18,'journal_and_lists'),(19,'milestones_stats_quiz'),(20,'social_feed_and_match'),(21,'monetization_members_newsletter'),(22,'extra_content_and_activities')]],'20260101002250_social_render_jobs.sql'],
 '005_complement_security_functions_views':['20260101002300_rls_complement.sql','20260101002400_views_and_counters.sql','20260101002450_realtime_complement.sql','20260101002500_functions_complement.sql'],
}
for name,files in groups.items():
 p=out/f'{name}.sql'; p.write_text('\n'.join(f'-- >>> {f}\n'+(m/f).read_text() for f in files))
 (out/f'{name}.manifest.txt').write_text('\n'.join(files)+'\n')
print('Built',len(groups),'remote apply bundles (seed is kept separate).')
