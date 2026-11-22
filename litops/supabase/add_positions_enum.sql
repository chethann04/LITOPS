-- ============================================================================
-- LitOps: Support Flexible Positions in Supabase Enum
-- Run this in Supabase Dashboard > SQL Editor > New Query > Run
-- ============================================================================

DO $$
BEGIN
  -- Add flexible position enums if they don't already exist
  BEGIN
    ALTER TYPE result_position ADD VALUE IF NOT EXISTS 'fourth_place';
  EXCEPTION WHEN duplicate_object THEN null;
  END;

  BEGIN
    ALTER TYPE result_position ADD VALUE IF NOT EXISTS 'fifth_place';
  EXCEPTION WHEN duplicate_object THEN null;
  END;

  BEGIN
    ALTER TYPE result_position ADD VALUE IF NOT EXISTS 'consolation';
  EXCEPTION WHEN duplicate_object THEN null;
  END;

  BEGIN
    ALTER TYPE result_position ADD VALUE IF NOT EXISTS 'special_mention';
  EXCEPTION WHEN duplicate_object THEN null;
  END;

  BEGIN
    ALTER TYPE result_position ADD VALUE IF NOT EXISTS 'participation';
  EXCEPTION WHEN duplicate_object THEN null;
  END;
END $$;
