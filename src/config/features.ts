export const MEMBER_ROLES = [
  "owner",
  "admin",
  "manager",
  "operator",
  "accountant",
  "viewer",
] as const;

export type MemberRole = (typeof MEMBER_ROLES)[number];

export const FEATURE_STATUSES = ["enabled", "disabled", "restricted"] as const;
export type FeatureStatus = (typeof FEATURE_STATUSES)[number];

export const FEATURE_CODES = [
  "dashboard",
  "sales",
  "purchases",
  "customers",
  "suppliers",
  "cash",
  "banks",
  "inventory",
  "pos",
  "accounting",
  "taxes",
  "payroll",
  "projects",
  "assets",
  "reports",
  "medical_legal",
] as const;

export type FeatureCode = (typeof FEATURE_CODES)[number];

export const BUSINESS_TYPES = [
  "kiosk",
  "retail",
  "professional",
  "services",
  "accounting_firm",
  "healthcare",
  "medical_legal",
  "industry",
  "other",
] as const;

export type BusinessType = (typeof BUSINESS_TYPES)[number];

export const BUSINESS_TYPE_LABELS: Record<BusinessType, string> = {
  kiosk: "Kiosco / comercio chico",
  retail: "Comercio minorista",
  professional: "Profesional",
  services: "Empresa de servicios",
  accounting_firm: "Estudio contable",
  healthcare: "Salud",
  medical_legal: "Servicios médico-legales",
  industry: "Industria",
  other: "Otro",
};

/** Central permission keys — extend here, not in components. */
export const PERMISSIONS = [
  "org.read",
  "org.update",
  "members.read",
  "members.invite",
  "members.manage_roles",
  "settings.read",
  "settings.update",
  "branches.read",
  "branches.manage",
  "fiscal.read",
  "fiscal.update",
  "business_profile.read",
  "business_profile.update",
  "features.read",
  "features.manage",
  "audit.read",
  "accounting.read",
  "accounting.manage_periods",
] as const;

export type Permission = (typeof PERMISSIONS)[number];

export const ROLE_PERMISSIONS: Record<MemberRole, readonly Permission[]> = {
  owner: PERMISSIONS,
  admin: [
    "org.read",
    "org.update",
    "members.read",
    "members.invite",
    "members.manage_roles",
    "settings.read",
    "settings.update",
    "branches.read",
    "branches.manage",
    "fiscal.read",
    "fiscal.update",
    "business_profile.read",
    "business_profile.update",
    "features.read",
    "features.manage",
    "audit.read",
    "accounting.read",
    "accounting.manage_periods",
  ],
  manager: [
    "org.read",
    "members.read",
    "settings.read",
    "branches.read",
    "branches.manage",
    "fiscal.read",
    "business_profile.read",
    "business_profile.update",
    "features.read",
    "audit.read",
    "accounting.read",
  ],
  operator: [
    "org.read",
    "members.read",
    "settings.read",
    "branches.read",
    "fiscal.read",
    "business_profile.read",
    "features.read",
  ],
  accountant: [
    "org.read",
    "members.read",
    "settings.read",
    "branches.read",
    "fiscal.read",
    "fiscal.update",
    "business_profile.read",
    "features.read",
    "audit.read",
    "accounting.read",
    "accounting.manage_periods",
  ],
  viewer: [
    "org.read",
    "members.read",
    "settings.read",
    "branches.read",
    "fiscal.read",
    "business_profile.read",
    "features.read",
    "audit.read",
    "accounting.read",
  ],
};

export const ROLE_LABELS: Record<MemberRole, string> = {
  owner: "Propietario",
  admin: "Administrador",
  manager: "Gerente",
  operator: "Operador",
  accountant: "Contador",
  viewer: "Solo lectura",
};
