-- ============================================================================
-- LitOps: Automatically Notify All 3rd & 4th Year Members on Event Results Published
-- ============================================================================
-- Triggers whenever an event's status changes to 'results_published'.
-- Sends in-app and push notifications to all active 3rd and 4th year members ONLY.
-- 1st and 2nd year members (junior_wing, assistant_coordinator) are strictly excluded.
--
-- How to apply:
-- 1. Open Supabase Dashboard -> SQL Editor
-- 2. Paste this script and click Run
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_senior_members_on_results_published()
RETURNS TRIGGER AS $$
DECLARE
  v_event_name TEXT;
  v_publisher_id UUID;
  v_rec RECORD;
  v_title TEXT;
  v_message TEXT;
BEGIN
  -- Only fire when status transitions to 'results_published'
  IF NEW.status::TEXT = 'results_published' AND (OLD.status IS NULL OR OLD.status::TEXT != 'results_published') THEN
    v_event_name := COALESCE(NEW.name, NEW.title, 'Event');
    v_publisher_id := auth.uid();
    v_title := '🏆 Results Published: ' || v_event_name;
    v_message := 'Results for "' || v_event_name || '" have been published. Check out the leaderboard for updated branch standings!';

    -- Loop through active 3rd and 4th year members ONLY
    FOR v_rec IN
      SELECT id, role, year, academic_year, usn
      FROM public.profiles
      WHERE is_active = true
        AND (account_status IS NULL OR account_status != 'disabled')
        AND (profile_status IS NULL OR profile_status != 'rejected')
        -- Strictly exclude 1st and 2nd year members
        AND NOT (
          year IN (1, 2) OR 
          academic_year IN (1, 2) OR 
          role::TEXT IN ('junior_wing', 'assistant_coordinator')
        )
        -- Strictly match 3rd and 4th year members
        AND (
          year IN (3, 4) OR
          academic_year IN (3, 4) OR
          (year IS NULL AND academic_year IS NULL AND role::TEXT NOT IN ('junior_wing', 'assistant_coordinator'))
        )
    LOOP
      -- Check if notification already exists to avoid duplicates
      IF NOT EXISTS (
        SELECT 1 FROM public.notifications
        WHERE user_id = v_rec.id 
          AND event_id = NEW.id 
          AND type = 'results_published'
      ) THEN
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
          NEW.id,
          NOW()
        );
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trg_notify_results_published ON public.events;
CREATE TRIGGER trg_notify_results_published
AFTER UPDATE OF status ON public.events
FOR EACH ROW
EXECUTE FUNCTION public.notify_senior_members_on_results_published();
