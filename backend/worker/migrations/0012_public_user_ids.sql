-- Assign every existing account a stable, unique 8-digit public ID.
-- Keep users.id UUID unchanged for authentication and relational integrity.
WITH numbered AS (
  SELECT user_id, ROW_NUMBER() OVER (ORDER BY user_id) AS row_num
  FROM profiles
  WHERE gabo_id IS NULL OR gabo_id = ''
),
seed AS (
  SELECT (abs(random()) % 90000000) AS start_value
)
UPDATE profiles
SET gabo_id = (
  SELECT printf('%08d', 10000000 + ((seed.start_value + numbered.row_num - 1) % 90000000))
  FROM numbered, seed
  WHERE numbered.user_id = profiles.user_id
)
WHERE gabo_id IS NULL OR gabo_id = '';
