import Link from "next/link";
import { brand } from "@/config/brand";
import { Button } from "@/components/ui/button";

export default function HomePage() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-[#05070a] text-[#f8fafc]">
      <div
        className="pointer-events-none absolute inset-0 opacity-70"
        style={{
          background:
            "radial-gradient(ellipse 80% 50% at 50% -20%, rgba(13,110,253,0.35), transparent), radial-gradient(ellipse 60% 40% at 100% 0%, rgba(36,150,255,0.15), transparent)",
        }}
      />
      <div className="relative mx-auto flex min-h-screen max-w-5xl flex-col justify-center px-6 py-16">
        <p className="text-sm font-semibold tracking-[0.2em] text-[#2496ff] uppercase">
          {brand.name}
        </p>
        <h1 className="mt-4 max-w-2xl text-4xl font-semibold tracking-tight sm:text-5xl">
          {brand.name}
        </h1>
        <p className="mt-4 max-w-xl text-lg text-[#cbd5e1]">{brand.tagline}</p>
        <p className="mt-3 max-w-xl text-sm text-[#94a3b8]">
          Vos administrás el negocio. La plataforma se ocupa de la contabilidad.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Button asChild>
            <Link href="/register">Empezar</Link>
          </Button>
          <Button asChild variant="outline">
            <Link href="/login">Ingresar</Link>
          </Button>
        </div>
      </div>
    </main>
  );
}
