-- Preserve every existing public player identifier while adopting the Happy ID name.
ALTER TABLE profiles RENAME COLUMN gabo_id TO happy_id;
