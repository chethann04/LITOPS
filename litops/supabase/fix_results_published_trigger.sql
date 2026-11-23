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
    v_event_name := COALESCE(NEW.title, 'Event');
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
