import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { OnboardingWizard } from "@/components/onboarding/onboarding-wizard";

export default async function OnboardingPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id, organizations ( onboarding_completed_at )")
    .eq("user_id", user.id)
    .eq("status", "active");

  const completed = memberships?.some((m) => {
    const org = m.organizations as unknown as {
      onboarding_completed_at: string | null;
    } | null;
    return Boolean(org?.onboarding_completed_at);
  });

  if (completed) {
    redirect("/dashboard");
  }

  return <OnboardingWizard />;
}
