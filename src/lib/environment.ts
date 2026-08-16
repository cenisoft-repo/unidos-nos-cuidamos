/**
 * Entorno de ejecución declarado. El valor por defecto es `sandbox`: la
 * divulgación de datos no productivos solo desaparece cuando alguien declara
 * explícitamente `production`, nunca por omisión.
 */
export const APP_ENV = process.env.NEXT_PUBLIC_APP_ENV ?? "sandbox";

/** `true` mientras la instancia sirva datos que no son operativos reales. */
export const servesNonProductionData = APP_ENV !== "production";
