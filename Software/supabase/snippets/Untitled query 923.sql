select conname, contype
from pg_constraint
where conrelid = 'students'::regclass;