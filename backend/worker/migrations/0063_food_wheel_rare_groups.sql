-- Persist rare group outcomes separately while retaining the existing bet-slot constraint.
ALTER TABLE food_wheel_rounds ADD COLUMN result_special TEXT CHECK (result_special IS NULL OR result_special IN ('pizza', 'salad'));
