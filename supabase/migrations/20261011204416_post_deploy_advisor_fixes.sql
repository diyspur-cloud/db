-- Address post-deploy advisor findings without changing stored rows.
-- The primary key already covers user_id; add a leading index for prompt_id FK.
CREATE INDEX IF NOT EXISTS user_challenge_prompt_progress_prompt_id_idx
  ON public.user_challenge_prompt_progress(prompt_id);

-- Keep the admin read path in the owner/admin SELECT policy, and scope writes
-- separately so the FOR ALL policy does not create a second permissive SELECT.
DROP POLICY IF EXISTS meeting_attendance_admin_write ON public.meeting_attendance;
DROP POLICY IF EXISTS meeting_attendance_admin_insert ON public.meeting_attendance;
DROP POLICY IF EXISTS meeting_attendance_admin_update ON public.meeting_attendance;
DROP POLICY IF EXISTS meeting_attendance_admin_delete ON public.meeting_attendance;

CREATE POLICY meeting_attendance_admin_insert ON public.meeting_attendance
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY meeting_attendance_admin_update ON public.meeting_attendance
  FOR UPDATE TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY meeting_attendance_admin_delete ON public.meeting_attendance
  FOR DELETE TO authenticated
  USING ((SELECT public.is_admin()));
