type AuthErrorLike = { code?: string | null; message?: string | null; status?: number | null } | null;

/** Supabase Auth errors come in English; users only ever see these Spanish texts. */
export function authErrorMessage(error: AuthErrorLike, context: "signup" | "login"): string {
  const code = error?.code ?? "";
  const message = (error?.message ?? "").toLowerCase();
  if (code === "email_address_invalid" || message.includes("is invalid")) {
    return "Ese email no es válido. Usá una dirección real donde puedas recibir correo.";
  }
  if (code === "user_already_exists" || code === "email_exists" || message.includes("already registered")) {
    return "Ya existe una cuenta con ese email. Ingresá o usá otro email.";
  }
  if (code === "weak_password" || message.includes("password should")) {
    return "La contraseña es muy débil. Usá al menos 8 caracteres combinando letras y números.";
  }
  if (code === "email_not_confirmed" || message.includes("not confirmed")) {
    return "Todavía no confirmaste tu email. Abrí el enlace que te enviamos y volvé a ingresar.";
  }
  if (code.startsWith("over_") || error?.status === 429 || message.includes("rate limit")) {
    return "Hubo demasiados intentos seguidos. Esperá unos minutos y probá de nuevo.";
  }
  if (context === "login") return "Email o contraseña incorrectos.";
  return "No se pudo crear la cuenta. Intentá de nuevo en unos minutos.";
}

/** Only same-site relative paths are accepted as post-auth destinations. */
export function safeNextPath(value: string | null | undefined, fallback = "/dashboard"): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return fallback;
  return value;
}
