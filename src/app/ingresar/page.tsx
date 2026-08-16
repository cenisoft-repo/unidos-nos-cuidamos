import type { Metadata } from "next";
import { servesNonProductionData } from "@/lib/environment";
import { login } from "./actions";

export const metadata: Metadata = { title: "Ingreso seguro" };

const PRACTICE_ACCOUNTS = [
  "admin@rutasolidaria.local",
  "aliado@rutasolidaria.local",
  "bodega@rutasolidaria.local",
  "solicita@rutasolidaria.local",
  "aprueba@rutasolidaria.local",
];

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; next?: string }> }) {
  const params = await searchParams;

  return (
    <div className="auth-layout">
      <section className="auth-copy">
        <div>
          <p className="eyebrow">Acceso operacional</p>
          <h1>Una sola historia.<br />El permiso justo.</h1>
          <p>Tu membresía determina la organización, el evento y las acciones disponibles.</p>
        </div>
        {servesNonProductionData && <p className="auth-note">Instancia de práctica · no uses credenciales reales</p>}
      </section>

      <section className="auth-form-wrap">
        <form action={login} className="auth-form">
          <h2>Ingresar</h2>
          <p style={{ color: "var(--muted)" }}>Accede al recorrido que corresponde a tu rol.</p>
          {params.error && <p className="form-error" role="alert">{params.error}</p>}
          <input type="hidden" name="next" value={params.next ?? "/operaciones"} />
          <div className="field">
            <label htmlFor="email">Correo</label>
            <input id="email" name="email" type="email" autoComplete="email" required />
          </div>
          <div className="field">
            <label htmlFor="password">Contraseña</label>
            <input id="password" name="password" type="password" autoComplete="current-password" required />
          </div>
          <button className="button button-dark button-block" type="submit">Ingresar</button>
          {servesNonProductionData && (
            <div className="demo-accounts">
              <strong>Cuentas de práctica</strong>
              {PRACTICE_ACCOUNTS.map((account) => <code key={account}>{account}</code>)}
            </div>
          )}
        </form>
      </section>
    </div>
  );
}
