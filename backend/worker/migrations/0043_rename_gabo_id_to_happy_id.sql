-- Rename the public identifier while preserving every existing value.
-- Keep a temporary synchronized legacy column so already-deployed clients remain compatible.
ALTER TABLE profiles RENAME COLUMN gabo_id TO happy_id;
ALTER TABLE profiles ADD COLUMN gabo_id TEXT;
UPDATE profiles SET gabo_id = happy_id;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_gabo_id_compat
  ON profiles(gabo_id) WHERE gabo_id IS NOT NULL AND gabo_id <> '';

CREATE TRIGGER IF NOT EXISTS profiles_sync_happy_id_to_legacy
AFTER UPDATE OF happy_id ON profiles
WHEN NEW.happy_id IS NOT OLD.happy_id
BEGIN
  UPDATE profiles SET gabo_id = NEW.happy_id WHERE user_id = NEW.user_id;
END;

CREATE TRIGGER IF NOT EXISTS profiles_sync_legacy_to_happy_id
AFTER UPDATE OF gabo_id ON profiles
WHEN NEW.gabo_id IS NOT OLD.gabo_id
BEGIN
  UPDATE profiles SET happy_id = NEW.gabo_id WHERE user_id = NEW.user_id;
END;
