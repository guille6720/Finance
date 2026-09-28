import { LoginForm } from "@/components/auth/login-form";

export default async function LoginPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = (await searchParams) ?? {};
  const notice = typeof params.aviso === "string" ? params.aviso : undefined;
  return (
    <main className="flex min-h-screen items-center justify-center bg-background p-4">
      <LoginForm notice={notice} />
    </main>
  );
}
