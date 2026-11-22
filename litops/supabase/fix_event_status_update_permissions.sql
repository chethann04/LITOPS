-- ============================================================================
-- LitOps: Fix Event Status and Event Management Permissions
-- Run this in Supabase Dashboard > SQL Editor > New Query > Run
-- ============================================================================

-- 1. Ensure RLS policies on events table allow all event managers, directors, presidents, and admins to update events
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super admin can update events" ON public.events;
DROP POLICY IF EXISTS "Admins and event managers can update events" ON public.events;
DROP POLICY IF EXISTS "Authorized roles can update events" ON public.events;
DROP POLICY IF EXISTS "Admins can update events" ON public.events;

CREATE POLICY "Authorized roles can update events" ON public.events
  FOR UPDATE
  TO authenticated
  USING (
    is_super_admin() OR
    is_admin() OR
    is_role('event_manager') OR
    is_role('event_manager_co_editorial') OR
    is_role('event_director') OR
    is_role('student_president') OR
    is_role('student_vice_president') OR
    created_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND (year = 4 OR role = 'super_admin'::user_role) AND is_active = true
    )
  )
  WITH CHECK (
    is_super_admin() OR
    is_admin() OR
    is_role('event_manager') OR
    is_role('event_manager_co_editorial') OR
    is_role('event_director') OR
    is_role('student_president') OR
    is_role('student_vice_president') OR
    created_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() AND (year = 4 OR role = 'super_admin'::user_role) AND is_active = true
    )
  );

-- 2. Ensure log_audit_action() trigger has SECURITY DEFINER so audit logging never blocks updates
CREATE OR REPLACE FUNCTION public.log_audit_action()
RETURNS TRIGGER AS $$
DECLARE
  v_action TEXT;
  v_entity_type TEXT;
BEGIN
  v_entity_type := TG_TABLE_NAME;
  
  IF TG_OP = 'INSERT' THEN
    v_action := 'CREATE';
    INSERT INTO public.audit_logs (action, entity_type, entity_id, details, created_at)
    VALUES (v_action, v_entity_type, NEW.id, to_jsonb(NEW), NOW());
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    v_action := 'UPDATE';
    INSERT INTO public.audit_logs (action, entity_type, entity_id, details, created_at)
    VALUES (v_action, v_entity_type, NEW.id, jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW)), NOW());
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'DELETE';
    INSERT INTO public.audit_logs (action, entity_type, entity_id, details, created_at)
    VALUES (v_action, v_entity_type, OLD.id, to_jsonb(OLD), NOW());
    RETURN OLD;
  END IF;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    -- Never allow audit logging failure to block business operations
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Dedicated SECURITY DEFINER RPC function for 100% foolproof event status updates
CREATE OR REPLACE FUNCTION public.update_event_status(
  p_event_id UUID,
  p_status TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_caller_role user_role;
  v_caller_year INT;
  v_updated events%ROWTYPE;
BEGIN
  -- Check authentication
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify caller
  SELECT role, year INTO v_caller_role, v_caller_year
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'User profile not found or inactive';
  END IF;

  -- Permission check: super_admin, admin, event_manager, event_director, 4th year, or creator
  IF NOT (
    v_caller_role = 'super_admin'::user_role OR
    v_caller_role = 'student_president'::user_role OR
    v_caller_role = 'student_vice_president'::user_role OR
    v_caller_role = 'joint_secretary'::user_role OR
    v_caller_role = 'event_director'::user_role OR
    v_caller_role = 'event_manager'::user_role OR
    v_caller_role = 'event_manager_co_editorial'::user_role OR
    v_caller_year = 4 OR
    EXISTS (SELECT 1 FROM public.events WHERE id = p_event_id AND created_by = auth.uid()) OR
    EXISTS (SELECT 1 FROM public.event_assignments WHERE event_id = p_event_id AND user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Permission denied to update event status';
  END IF;

  -- Update event
  UPDATE public.events
  SET status = p_status::event_status,
      updated_at = NOW()
  WHERE id = p_event_id
  RETURNING * INTO v_updated;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event % not found', p_event_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_updated.id, 'status', v_updated.status);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Enable realtime publication for events
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE events;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
END $$;
ALTER TABLE events REPLICA IDENTITY FULL;
