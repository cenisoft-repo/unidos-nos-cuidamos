"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { BadgeCheck, CheckCircle2, History, KeyRound, LoaderCircle, ListTree, Users } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { EVENT_ID } from "@/lib/constants";
import { toOperationalMessage } from "@/lib/user-errors";
import { formatDate } from "@/lib/format";

export type PlatformUser = {
  user_id: string;
  email: string;
  full_name: string | null;
  is_super_admin: boolean;
  active_roles: string[];
  inactive_roles: string[];
  organizations: string[];
  location_scope: string[];
  last_sign_in_at: string | null;
};

export type PlatformCatalog = {
  key: string;
  name: string;
  version: number;
  values_json: unknown[];
  effective_from: string;
};

export type PlatformAuditEntry = {
  occurred_at: string;
  actor_email: string | null;
  action: string;
  entity_table: string;
  entity_id: string | null;
  organization_name: string | null;
  metadata: Record<string, unknown> | null;
};

export type OrganizationOption = { id: string; name: string; status: string; verified: boolean };

export type OrganizationVerification = {
  organization_id: string;
  organization_name: string;
  operational: boolean;
  verification_state: string;
  verification_method: string | null;
  decided_at: string | null;
};

/*
 * G-039: confirmar el correo y comprobar la organizacion son hechos distintos, y la
 * pantalla tiene que decirlo. `operativa` es la habilitacion para trabajar; el estado
 * es el nivel de comprobacion alcanzado.
 */
const VERIFICATION_LABEL: Record<string, string> = {
  pending: "Sin comprobar",
  email_verified: "Correo confirmado",
  document_pending: "Documentos pendientes",
  verified: "Organización verificada",
  rejected: "Rechazada",
  expired: "Vencida",
};

/*
 * Los roles que la consola reparte. `super_admin` no está aquí a propósito: la autoridad
 * global no se concede desde una pantalla, y la RPC la rechaza aunque alguien altere el
 * cliente. Lo que se ve aquí y lo que la base acepta dicen lo mismo.
 */
const ASSIGNABLE_ROLES: { value: string; label: string }[] = [
  { value: "event_admin", label: "Administración de evento" },
  { value: "verifier", label: "Verificación" },
  { value: "partner_reporter", label: "Aliado reportante" },
  { value: "warehouse_operator", label: "Centro de acopio" },
  { value: "logistics_operator", label: "Logística" },
  { value: "treasury_requester", label: "Solicitudes de tesorería" },
  { value: "treasury_approver", label: "Aprobación financiera" },
  { value: "auditor", label: "Auditoría" },
];

// `super_admin` se muestra pero no se reparte: aparece aquí solo para poder nombrarlo.
const ROLE_LABEL = new Map([...ASSIGNABLE_ROLES.map((role) => [role.value, role.label] as const), ["super_admin", "Autoridad global"] as const]);

type Tab = "usuarios" | "organizaciones" | "catalogos" | "auditoria";

function catalogToText(values: unknown[]) {
  return JSON.stringify(values, null, 2);
}

export function PlatformParameterization({
  users,
  catalogs,
  audit,
  organizations,
  verifications,
  currentUserId,
}: {
  users: PlatformUser[];
  catalogs: PlatformCatalog[];
  audit: PlatformAuditEntry[];
  organizations: OrganizationOption[];
  verifications: OrganizationVerification[];
  currentUserId: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [tab, setTab] = useState<Tab>("usuarios");
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [done, setDone] = useState("");

  const [targetUser, setTargetUser] = useState(users.find((user) => user.user_id !== currentUserId && !user.is_super_admin)?.user_id ?? "");
  const [targetOrganization, setTargetOrganization] = useState(organizations[0]?.id ?? "");
  const [targetRole, setTargetRole] = useState(ASSIGNABLE_ROLES[0].value);
  const [targetActive, setTargetActive] = useState(true);

  const [verificationNote, setVerificationNote] = useState("");
  const [catalogKey, setCatalogKey] = useState(catalogs[0]?.key ?? "");
  const selectedCatalog = catalogs.find((catalog) => catalog.key === catalogKey);
  const [catalogDraft, setCatalogDraft] = useState(selectedCatalog ? catalogToText(selectedCatalog.values_json) : "");
  const [catalogNote, setCatalogNote] = useState("");

  function selectCatalog(key: string) {
    setCatalogKey(key);
    const next = catalogs.find((catalog) => catalog.key === key);
    setCatalogDraft(next ? catalogToText(next.values_json) : "");
    setCatalogNote("");
    setError("");
    setDone("");
  }

  async function run(label: string, action: () => PromiseLike<{ error: { message?: string | null; code?: string | null } | null }>) {
    setBusy(label);
    setError("");
    setDone("");
    const { error: failure } = await action();
    setBusy("");
    if (failure) {
      setError(toOperationalMessage(failure));
      return false;
    }
    setDone(label);
    router.refresh();
    return true;
  }

  async function applyRole() {
    await run(targetActive ? "Rol asignado" : "Rol revocado", () =>
      supabase.rpc("assign_membership_role", {
        p_user_id: targetUser,
        p_organization_id: targetOrganization,
        p_event_id: EVENT_ID,
        p_role: targetRole,
        p_active: targetActive,
      }),
    );
  }

  async function toggleAccess(user: PlatformUser) {
    const activating = user.active_roles.length === 0;
    await run(activating ? "Cuenta activada" : "Cuenta desactivada", () =>
      supabase.rpc("set_user_platform_access", { p_user_id: user.user_id, p_active: activating }),
    );
  }

  async function decideVerification(organizationId: string, decision: string) {
    await run("Verificación registrada", () =>
      supabase.rpc("decide_organization_verification", {
        p_organization_id: organizationId,
        p_event_id: EVENT_ID,
        p_decision: decision,
        p_note: verificationNote,
      }),
    );
  }

  async function publishCatalog() {
    let parsed: unknown;
    try {
      parsed = JSON.parse(catalogDraft);
    } catch {
      setError("La lista de valores no es un JSON válido.");
      return;
    }
    if (!Array.isArray(parsed)) {
      setError("El catálogo tiene que ser una lista de valores.");
      return;
    }
    const published = await run("Catálogo publicado", () =>
      supabase.rpc("manage_catalog_values", { p_key: catalogKey, p_values: parsed, p_note: catalogNote }),
    );
    if (published) setCatalogNote("");
  }

  return (
    <div className="param-shell">
      <div className="param-tabs" role="tablist" aria-label="Secciones de parametrización">
        <button role="tab" aria-selected={tab === "usuarios"} className={tab === "usuarios" ? "is-selected" : ""} type="button" onClick={() => setTab("usuarios")}>
          <Users size={16} /> Usuarios y roles
        </button>
        <button role="tab" aria-selected={tab === "organizaciones"} className={tab === "organizaciones" ? "is-selected" : ""} type="button" onClick={() => setTab("organizaciones")}>
          <BadgeCheck size={16} /> Organizaciones
        </button>
        <button role="tab" aria-selected={tab === "catalogos"} className={tab === "catalogos" ? "is-selected" : ""} type="button" onClick={() => setTab("catalogos")}>
          <ListTree size={16} /> Catálogos
        </button>
        <button role="tab" aria-selected={tab === "auditoria"} className={tab === "auditoria" ? "is-selected" : ""} type="button" onClick={() => setTab("auditoria")}>
          <History size={16} /> Auditoría
        </button>
      </div>

      {error && <p className="form-error" role="alert">{error}</p>}
      {done && !error && <p className="form-success" role="status"><CheckCircle2 size={15} /> {done}</p>}

      {tab === "usuarios" && (
        <section className="ops-panel" aria-labelledby="param-users-title">
          <header className="ops-panel-header">
            <div>
              <h2 id="param-users-title">Usuarios y alcance</h2>
              <p>El alcance de un administrador se define asignándole organizaciones y bodegas, no creando un rol nuevo por cada bodega.</p>
            </div>
            <span>{users.length} cuentas</span>
          </header>

          <div className="param-assign">
            <div className="field">
              <label htmlFor="param-user">Cuenta</label>
              <select id="param-user" value={targetUser} onChange={(event) => setTargetUser(event.target.value)}>
                {users
                  .filter((user) => user.user_id !== currentUserId && !user.is_super_admin)
                  .map((user) => <option key={user.user_id} value={user.user_id}>{user.full_name ?? user.email}</option>)}
              </select>
            </div>
            <div className="field">
              <label htmlFor="param-organization">Organización</label>
              <select id="param-organization" value={targetOrganization} onChange={(event) => setTargetOrganization(event.target.value)}>
                {organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}
              </select>
            </div>
            <div className="field">
              <label htmlFor="param-role">Rol</label>
              <select id="param-role" value={targetRole} onChange={(event) => setTargetRole(event.target.value)}>
                {ASSIGNABLE_ROLES.map((role) => <option key={role.value} value={role.value}>{role.label}</option>)}
              </select>
            </div>
            <div className="field">
              <label htmlFor="param-action">Acción</label>
              <select id="param-action" value={targetActive ? "grant" : "revoke"} onChange={(event) => setTargetActive(event.target.value === "grant")}>
                <option value="grant">Asignar</option>
                <option value="revoke">Revocar</option>
              </select>
            </div>
            <button className="button button-dark" type="button" disabled={!!busy || !targetUser} onClick={applyRole}>
              {busy ? <LoaderCircle className="spin" size={16} /> : <KeyRound size={16} />} {targetActive ? "Asignar rol" : "Revocar rol"}
            </button>
          </div>
          <p className="param-note">
            <KeyRound size={13} aria-hidden="true" /> SUPER_ADMIN no aparece en la lista: se concede por una operación
            privilegiada y auditada fuera de la aplicación, y nadie puede otorgárselo a sí mismo.
          </p>

          <div className="report-scroll">
            <table className="report-table">
              <caption className="visually-hidden">Cuentas con sus roles activos, organizaciones y alcance por bodega</caption>
              <thead>
                <tr><th scope="col">Cuenta</th><th scope="col">Roles activos</th><th scope="col">Organizaciones</th><th scope="col">Bodegas asignadas</th><th scope="col">Acciones</th></tr>
              </thead>
              <tbody>
                {users.map((user) => (
                  <tr key={user.user_id}>
                    <th scope="row">
                      <strong>{user.full_name ?? user.email}</strong>
                      <small>{user.email}</small>
                      {user.is_super_admin && <small className="param-flag">Autoridad global</small>}
                    </th>
                    <td>
                      {user.active_roles.length
                        ? user.active_roles.map((role) => <span className="param-chip" key={role}>{ROLE_LABEL.get(role) ?? role}</span>)
                        : <em>Sin acceso vigente</em>}
                    </td>
                    <td>{user.organizations.join(" · ") || "—"}</td>
                    <td>{user.location_scope.length ? user.location_scope.join(" · ") : "Todas las de su organización"}</td>
                    <td>
                      {user.is_super_admin || user.user_id === currentUserId
                        ? <small>Se administra fuera de la consola</small>
                        : <button className="button button-outline button-small" type="button" disabled={!!busy} onClick={() => toggleAccess(user)}>
                            {user.active_roles.length ? "Desactivar" : "Activar"}
                          </button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab === "organizaciones" && (
        <section className="ops-panel" aria-labelledby="param-orgs-title">
          <header className="ops-panel-header">
            <div>
              <h2 id="param-orgs-title">Organizaciones y su comprobación</h2>
              <p>Confirmar un correo no es verificar una organización: lo primero abre el buzón, lo segundo exige una revisión humana.</p>
            </div>
            <span>{verifications.length} organizaciones</span>
          </header>
          <div className="field param-verification-note">
            <label htmlFor="param-verification-note">Sustento de la decisión</label>
            <input id="param-verification-note" value={verificationNote} maxLength={200} onChange={(event) => setVerificationNote(event.target.value)} placeholder="Qué se revisó y con qué documento" />
          </div>
          <div className="report-scroll">
            <table className="report-table">
              <caption className="visually-hidden">Organizaciones con su nivel de comprobación</caption>
              <thead>
                <tr><th scope="col">Organización</th><th scope="col">Opera</th><th scope="col">Comprobación</th><th scope="col">Método</th><th scope="col">Decisión</th></tr>
              </thead>
              <tbody>
                {verifications.map((row) => (
                  <tr key={row.organization_id}>
                    <th scope="row">{row.organization_name}</th>
                    <td>{row.operational ? "Sí" : "No"}</td>
                    <td><span className="param-chip">{VERIFICATION_LABEL[row.verification_state] ?? row.verification_state}</span></td>
                    <td><small>{row.verification_method ?? "—"}</small></td>
                    <td className="param-verification-actions">
                      <button className="button button-outline button-small" type="button" disabled={!!busy} onClick={() => decideVerification(row.organization_id, "request_documents")}>Pedir documentos</button>
                      <button className="button button-outline button-small" type="button" disabled={!!busy} onClick={() => decideVerification(row.organization_id, "verify")}>Verificar</button>
                      <button className="button button-outline button-small" type="button" disabled={!!busy} onClick={() => decideVerification(row.organization_id, "reject")}>Rechazar</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="param-note">Cada decisión se añade al historial con su sustento; la anterior no se sobrescribe.</p>
        </section>
      )}

      {tab === "catalogos" && (
        <section className="ops-panel" aria-labelledby="param-catalog-title">
          <header className="ops-panel-header">
            <div>
              <h2 id="param-catalog-title">Catálogos parametrizables</h2>
              <p>Publicar una lista crea una versión nueva y cierra la anterior; los aportes ya registrados conservan la versión con la que se validaron.</p>
            </div>
            <span>{catalogs.length} catálogos</span>
          </header>

          <div className="param-catalog-picker">
            {catalogs.map((catalog) => (
              <button key={catalog.key} type="button" aria-pressed={catalog.key === catalogKey} className={catalog.key === catalogKey ? "is-selected" : ""} onClick={() => selectCatalog(catalog.key)}>
                <strong>{catalog.name}</strong>
                <small>v{catalog.version} · {catalog.values_json.length} valores</small>
              </button>
            ))}
          </div>

          {selectedCatalog && (
            <div className="param-catalog-editor">
              <div className="field">
                <label htmlFor="param-catalog-values">Valores vigentes (JSON)</label>
                <textarea id="param-catalog-values" rows={14} value={catalogDraft} onChange={(event) => setCatalogDraft(event.target.value)} spellCheck={false} />
              </div>
              <div className="field">
                <label htmlFor="param-catalog-note">Motivo del cambio</label>
                <input id="param-catalog-note" value={catalogNote} maxLength={200} onChange={(event) => setCatalogNote(event.target.value)} placeholder="Queda en la auditoría junto al antes y el después" />
              </div>
              <button className="button button-dark" type="button" disabled={!!busy} onClick={publishCatalog}>
                {busy === "Catálogo publicado" ? <LoaderCircle className="spin" size={16} /> : <ListTree size={16} />} Publicar versión {selectedCatalog.version + 1}
              </button>
              <p className="param-note">
                Las reglas de autorización, las transiciones del despacho, las fórmulas de disponibilidad y los tipos del
                Kardex no se editan aquí: son contratos del sistema, no datos.
              </p>
            </div>
          )}
        </section>
      )}

      {tab === "auditoria" && (
        <section className="ops-panel" aria-labelledby="param-audit-title">
          <header className="ops-panel-header">
            <div>
              <h2 id="param-audit-title">Quién cambió qué y cuándo</h2>
              <p>Cada cambio administrativo con su actor, su entidad y el valor anterior y nuevo.</p>
            </div>
            <span>{audit.length} registros</span>
          </header>
          <div className="report-scroll">
            <table className="report-table">
              <caption className="visually-hidden">Auditoría de cambios administrativos</caption>
              <thead>
                <tr><th scope="col">Cuándo</th><th scope="col">Quién</th><th scope="col">Qué</th><th scope="col">Antes → después</th></tr>
              </thead>
              <tbody>
                {audit.length ? audit.map((entry, index) => (
                  <tr key={`${entry.occurred_at}-${index}`}>
                    <th scope="row">{formatDate(entry.occurred_at)}</th>
                    <td>{entry.actor_email ?? "Sistema"}</td>
                    <td><strong>{entry.action}</strong><small>{entry.entity_table}{entry.organization_name ? ` · ${entry.organization_name}` : ""}</small></td>
                    <td>
                      {entry.metadata?.valor_anterior || entry.metadata?.valor_nuevo
                        ? <code className="param-diff">{JSON.stringify(entry.metadata?.valor_anterior ?? null)} → {JSON.stringify(entry.metadata?.valor_nuevo ?? null)}</code>
                        : <small>{Array.isArray(entry.metadata?.changed_fields) ? (entry.metadata?.changed_fields as string[]).join(", ") : "—"}</small>}
                    </td>
                  </tr>
                )) : <tr><td colSpan={4}><p className="ops-empty">Todavía no hay cambios administrativos registrados.</p></td></tr>}
              </tbody>
            </table>
          </div>
        </section>
      )}
    </div>
  );
}
