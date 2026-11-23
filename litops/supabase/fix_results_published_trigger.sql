-- ============================================================================
-- LitOps: Automatically Notify All 3rd & 4th Year Members on Event Results Published
-- ============================================================================
-- Sends in-app and push notifications to all active 3rd and 4th year members ONLY.
-- 1st and 2nd year members (junior_wing, assistant_coordinator) are strictly excluded.
--
-- How to apply:
-- 1. Open Supabase Dashboard -> SQL Editor
-- 2. Paste this entire script and click Run
-- ============================================================================

-- 1. Ensure RLS policies allow authenticated users to insert/read notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
CREATE POLICY "Authenticated users can insert notifications"
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 2. Database RPC Function: notify_senior_members_on_results_published_rpc
-- Can be called directly from Flutter or internally from triggers
CREATE OR REPLACE FUNCTION public.notify_senior_members_on_results_published_rpc(
  p_event_id UUID,
  p_event_name TEXT,
  p_summary_text TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
  v_publisher_id UUID;
  v_rec RECORD;
  v_title TEXT;
  v_message TEXT;
  v_count INTEGER := 0;
BEGIN
  v_publisher_id := auth.uid();
  v_title := '🏆 Results Published: ' || COALESCE(p_event_name, 'Event');
  v_message := 'Results for "' || COALESCE(p_event_name, 'Event') || '" have been published.';
  
  IF p_summary_text IS NOT NULL AND TRIM(p_summary_text) != '' THEN
    v_message := v_message || E'\n' || TRIM(p_summary_text);
  END IF;
  
  v_message := v_message || E'\nCheck out the leaderboard for updated branch standings!';

  -- Clear previous results notifications for this event so re-publishing delivers fresh notifications
  DELETE FROM public.notifications
  WHERE event_id = p_event_id
    AND type = 'results_published';

  -- Loop through all active 3rd and 4th year members (excluding 1st and 2nd years)
  FOR v_rec IN
    SELECT id, role, year, usn
    FROM public.profiles
    WHERE (is_active IS NULL OR is_active = true)
      AND (profile_status IS NULL OR profile_status != 'rejected')
      -- Exclude publisher (the member publishing results doesn't need to notify themselves)
      AND (v_publisher_id IS NULL OR id != v_publisher_id)
      -- Strictly exclude 1st and 2nd year members
      AND NOT (
        year IN (1, 2) OR 
        role::TEXT IN ('junior_wing', 'assistant_coordinator')
      )
      -- Strictly match 3rd and 4th year members, or senior roles
      AND (
        year IN (3, 4) OR
        (year IS NULL AND role::TEXT NOT IN ('junior_wing', 'assistant_coordinator'))
      )
  LOOP
    INSERT INTO public.notifications (
      user_id,
      sender_user_id,
      title,
      message,
      type,
      is_read,
      event_id,
      created_at
    ) VALUES (
      v_rec.id,
      v_publisher_id,
      v_title,
      v_message,
      'results_published',
      false,
      p_event_id,
      NOW()
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.notify_senior_members_on_results_published_rpc(UUID, TEXT, TEXT) TO authenticated, anon;

-- 3. Automatic Trigger Function on public.events
CREATE OR REPLACE FUNCTION public.notify_senior_members_on_results_published()
RETURNS TRIGGER AS $$
DECLARE
  v_event_name TEXT;
BEGIN
  -- Fire whenever status is set to 'results_published'
  IF NEW.status::TEXT = 'results_published' THEN
    BEGIN
      v_event_name := COALESCE(NEW.name, 'Event');
    EXCEPTION WHEN OTHERS THEN
      v_event_name := 'Event';
    END;
    PERFORM public.notify_senior_members_on_results_published_rpc(NEW.id, v_event_name, NULL);
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Safety fallback: never abort event status updates
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger cleanly on public.events
DROP TRIGGER IF EXISTS trg_notify_results_published ON public.events;
CREATE TRIGGER trg_notify_results_published
AFTER UPDATE OF status ON public.events
FOR EACH ROW
EXECUTE FUNCTION public.notify_senior_members_on_results_published();

-- 4. Robust calculate_sarvottam_points trigger function with fail-safe error handling
CREATE OR REPLACE FUNCTION public.calculate_sarvottam_points()
RETURNS TRIGGER AS $$
DECLARE
  v_points INTEGER := 0;
  v_reason TEXT := '';
  v_branch TEXT;
  v_event_id UUID;
  v_student_id UUID;
BEGIN
  SELECT event_id, student_id INTO v_event_id, v_student_id FROM public.registrations WHERE id = NEW.registration_id;
  
  IF v_student_id IS NOT NULL THEN
    SELECT branch INTO v_branch FROM public.student_master WHERE id = v_student_id;
  END IF;

  IF v_branch IS NULL AND NEW.team_id IS NOT NULL THEN
    SELECT branch INTO v_branch FROM public.teams WHERE id = NEW.team_id;
  END IF;

  CASE NEW.position::TEXT
    WHEN 'winner' THEN v_points := COALESCE(NEW.score, 10); v_reason := 'Winner';
    WHEN 'runner_up' THEN v_points := COALESCE(NEW.score, 7); v_reason := 'Runner-Up';
    WHEN 'second_runner_up' THEN v_points := COALESCE(NEW.score, 5); v_reason := 'Second Runner-Up';
    ELSE
      v_points := COALESCE(NEW.score, 0);
      v_reason := COALESCE(NEW.remarks, 'Position Award');
  END CASE;

  IF v_branch IS NOT NULL AND v_points > 0 THEN
    INSERT INTO public.sarvottam_points (event_id, branch, student_id, team_id, points, reason, position)
    VALUES (COALESCE(v_event_id, NEW.event_id), v_branch, v_student_id, NEW.team_id, v_points, v_reason, NEW.position);
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Never allow point calculation exception to abort result insertion
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
