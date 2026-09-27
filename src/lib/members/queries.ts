/**
 * organization_members has two FKs to profiles (user_id, invited_by); embedding
 * `profiles` without a hint is ambiguous in PostgREST (PGRST201). The member's own
 * profile is the one referenced by user_id.
 */
export const ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT =
  "id, role, status, user_id, profiles!organization_members_user_id_fkey ( full_name, email )";
