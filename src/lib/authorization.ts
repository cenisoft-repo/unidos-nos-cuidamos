/*
 * Alcance de rol en las superficies operativas.
 *
 * La autoridad global no se representa con un rol distinto por pantalla: es una fila más
 * en `memberships`, y en la base la reconocen las cuatro funciones de compuerta. Aquí se
 * hace lo mismo para que la interfaz y la base digan siempre lo mismo: quien tiene
 * `super_admin` pasa cualquier comprobación de rol, sin lógica de negocio aparte.
 *
 * Ojo: esto decide qué se muestra, no qué se permite. Lo que se permite lo sigue
 * decidiendo PostgreSQL en cada RPC y en cada política.
 */
export const SUPER_ADMIN_ROLE = "super_admin";

export function isSuperAdminRole(roles: Set<string>) {
  return roles.has(SUPER_ADMIN_ROLE);
}

export function hasOperationalRole(roles: Set<string>, allowed: readonly string[]) {
  return isSuperAdminRole(roles) || allowed.some((role) => roles.has(role));
}
