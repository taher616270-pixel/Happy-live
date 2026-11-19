-- Give existing rooms without a cover a one-time copy of the owner's
-- current profile avatar. The copied URL is stored in rooms.image_url and
-- can then be changed independently from the owner's profile.
UPDATE rooms
SET image_url = (
  SELECT p.avatar_key
  FROM profiles p
  WHERE p.user_id = rooms.owner_user_id
    AND p.avatar_key LIKE 'https://%'
  LIMIT 1
)
WHERE (image_url IS NULL OR TRIM(image_url) = '')
  AND EXISTS (
    SELECT 1
    FROM profiles p
    WHERE p.user_id = rooms.owner_user_id
      AND p.avatar_key LIKE 'https://%'
  );
