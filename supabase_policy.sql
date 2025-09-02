-- Enable RLS for user table
ALTER TABLE public.user ENABLE ROW LEVEL SECURITY;

-- Remove any conflicting policies
DROP POLICY IF EXISTS "admin can view all users" ON public.user;

-- Allow only admins to select/view all users
CREATE POLICY "admin can view all users"
ON public.user
FOR SELECT
USING (
  EXISTS (SELECT 1 FROM public.admin WHERE id = auth.uid())
);
